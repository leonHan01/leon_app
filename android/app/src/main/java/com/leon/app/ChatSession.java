package com.leon.app;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import org.json.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

/** Retained across rotations. All state changes occur on the main looper. */
final class ChatSession {
    interface Listener { void changed(); void error(String message); }
    static final class ScrollPosition {final long message;final int top,offset;ScrollPosition(long message,int top,int offset){this.message=message;this.top=top;this.offset=offset;}}
    final Map<String,ScrollPosition> scrollPositions=new HashMap<>();
    final SharedPreferences prefs;
    final SecretStore secrets;
    final String deviceId;
    MessageApi.User user;
    String server, sender, status = "尚未连接", draft = "";
    MessageApi.Quote quotedMessage;
    private final Map<String,MessageApi.Quote> quoteDrafts=new HashMap<>();
    private final Set<Long> favoriteRequests=new HashSet<>();
    void quote(MessageApi.Message message){
        if(message.id<=0||!message.conversationId.equals(selectedConversation))return;
        try{quotedMessage=new MessageApi.Quote(message);notifyChanged();}catch(Exception e){report(e);}
    }
    void cancelQuote(){quotedMessage=null;notifyChanged();}
    void favorite(MessageApi.Message message,java.util.function.Consumer<String> notice){
        if(api==null||message.id<=0||!favoriteRequests.add(message.id))return;
        int connection=connectionGeneration;MessageApi client=api;
        navigationWorkers.execute(()->{
            try{client.addFavorite(message.id);main.post(()->{if(connection==connectionGeneration){favoriteRequests.remove(message.id);notice.accept("已收藏");}});}
            catch(Exception error){main.post(()->{if(connection==connectionGeneration){favoriteRequests.remove(message.id);searchFailure(error);report(error);}});}
        });
    }

    final List<ChatDocument> draftDocuments=new ArrayList<>();
    private final Map<String,List<ChatDocument>> documentDrafts=new HashMap<>();
    int preparingDocuments,documentEpoch,documentPickerConnection;String documentPickerRoom="";
    void addDocuments(List<android.net.Uri> uris,String room,int connection){
        if(api==null||room.isEmpty()||connection!=connectionGeneration)return;
        int count=room.equals(selectedConversation)?draftDocuments.size():documentDrafts.getOrDefault(room,List.of()).size();
        if(uris.isEmpty()||count+preparingDocuments+uris.size()>4){report(new java.io.IOException("每条消息最多发送 4 个文档。"));return;}
        int epoch=documentEpoch;preparingDocuments+=uris.size();notifyChanged();
        avatarWorkers.execute(()->{
            List<ChatDocument> result=new ArrayList<>();Exception error=null;
            try{for(var uri:uris)result.add(ChatDocument.read(resolver,uri));}catch(Exception e){error=e;}
            Exception failure=error;main.post(()->{
                if(epoch!=documentEpoch||connection!=connectionGeneration)return;preparingDocuments-=uris.size();
                if(failure!=null)report(failure);else if(room.equals(selectedConversation))draftDocuments.addAll(result);else documentDrafts.computeIfAbsent(room,k->new ArrayList<>()).addAll(result);notifyChanged();
            });
        });
    }
    void removeDocument(String id){draftDocuments.removeIf(doc->doc.id.equals(id));notifyChanged();}
    static List<ChatDocument> documents(JSONObject message){try{return ChatDocument.parse(message.optJSONArray("documents"));}catch(Exception e){return List.of();}}
    final List<ChatImage> draftImages = new ArrayList<>();
    ChatImageActions.Document imageExport;
    private final Map<String,List<ChatImage>> imageDrafts = new HashMap<>();
    private final java.io.File files;
    private final android.content.ContentResolver resolver;
    private final ChatImageLoader imageLoader = new ChatImageLoader();
    void refreshImages(){imageLoader.refresh();}
    void bindImage(android.widget.ImageView view,String id){bindImage(view,id,false);}
    void bindImage(android.widget.ImageView view,String id,boolean large){
        imageLoader.bind(view,connectionGeneration+":"+id,imageSource(id),large);
    }
    ChatImageLoader.Source imageSource(String id){
        MessageApi client=api;String scope=pendingKey;
        return ()->{
            byte[] local=ChatImage.local(files,scope,id);if(local!=null)return local;
            if(client==null)throw new java.io.IOException("请先连接服务器");return client.image(id);
        };
    }
    static List<String> imageIds(JSONObject message){
        var ids=message.optJSONArray("imageIds");var result=new ArrayList<String>();
        if(ids!=null)for(int i=0;i<ids.length();i++)result.add(ids.optString(i));return result;
    }
    private void removeImageFiles(JSONObject message){for(var doc:documents(message))ChatDocument.remove(files,pendingKey,doc.id);for(String id:imageIds(message))ChatImage.remove(files,pendingKey,id);}
    int preparingImages;
    boolean canSend(String text) { return configured() && !openingConversation() && !configuring && !toolsBusy && preparingImages==0 && preparingDocuments==0 && (!text.trim().isEmpty() || !draftImages.isEmpty() || !draftDocuments.isEmpty()) && text.length()<=8000; }
    void addImage(android.net.Uri uri,Runnable release) {
        if(api==null||configuring||draftImages.size()+preparingImages>=4){release.run();report(new java.io.IOException("请先连接服务器，每条最多 4 张图片"));return;}
        int connection=connectionGeneration;String room=selectedConversation;preparingImages++;notifyChanged();
        avatarWorkers.execute(()->{
            ChatImage image=null;Exception failure=null;
            try{image=ChatImage.read(resolver,uri);}catch(Exception e){failure=e;}finally{release.run();}
            ChatImage result=image;Exception error=failure;
            main.post(()->{
                preparingImages--;if(connection!=connectionGeneration){notifyChanged();return;}
                if(result!=null){if(room.equals(selectedConversation))draftImages.add(result);else imageDrafts.computeIfAbsent(room,k->new ArrayList<>()).add(result);}
                else report(error);notifyChanged();
            });
        });
    }
    void removeImage(String id){draftImages.removeIf(image->image.id.equals(id));notifyChanged();}
    boolean connected, hasOlder, loadingOlder, configuring, active, initialLoaded;
    long revision;
    final List<MessageApi.Message> messages = new ArrayList<>();
    final List<MessageApi.Agent> agents = new ArrayList<>();
    final List<MessageApi.ModelUsage> modelUsage=new ArrayList<>();
    boolean usageBusy;
    long usageLoadedAt;
    String usageError="";
    private final ExecutorService usageWorker=Executors.newSingleThreadExecutor();
    void loadUsage(){
        if(api==null||usageBusy||configuring)return;
        int connection=connectionGeneration;MessageApi client=api;
        usageBusy=true;usageError="";notifyChanged();
        usageWorker.execute(()->{
            try{
                var rows=client.usage();
                main.post(()->{
                    if(connection!=connectionGeneration)return;
                    modelUsage.clear();modelUsage.addAll(rows);usageLoadedAt=System.currentTimeMillis();usageBusy=false;notifyChanged();
                });
            }catch(Exception failure){main.post(()->{
                if(connection!=connectionGeneration)return;
                usageError=failure.getMessage()==null?"无法读取用量，请重试。":failure.getMessage();usageBusy=false;notifyChanged();
            });}
        });
    }
    final List<MessageApi.Conversation> conversations = new ArrayList<>();
    final List<MessageApi.Job> jobs = new ArrayList<>();
    private final Set<String> dismissedJobKeys=new HashSet<>();
    List<MessageApi.Job> visibleJobs(){
        List<MessageApi.Job> visible=new ArrayList<>();
        for(var job:jobs)if(!job.status.equals("FAILED")||!dismissedJobKeys.contains(dismissalKey(job)))visible.add(job);
        return visible;
    }
    int dismissedFailureCount(){return jobs.size()-visibleJobs().size();}
    private String jobId(MessageApi.Job job){return job.messageId+":"+job.agentId;}
    private String dismissalKey(MessageApi.Job job){
        try{
            byte[] hash=MessageDigest.getInstance("SHA-256").digest(job.error.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex=new StringBuilder();for(byte b:hash)hex.append(String.format(Locale.ROOT,"%02x",b));
            return jobId(job)+"#"+hex;
        }catch(java.security.NoSuchAlgorithmException impossible){throw new IllegalStateException(impossible);}
    }
    void dismissJob(MessageApi.Job job){
        if(!job.status.equals("FAILED"))return;
        dismissedJobKeys.add(dismissalKey(job));saveDismissals();revision++;notifyChanged();
    }
    void restoreDismissedJobs(){
        for(var job:jobs)if(job.status.equals("FAILED"))dismissedJobKeys.remove(dismissalKey(job));
        saveDismissals();revision++;notifyChanged();
    }
    private void saveDismissals(){
        if(pendingKey!=null)prefs.edit().putStringSet(pendingKey+".dismissedJobs",new HashSet<>(dismissedJobKeys)).apply();
    }
    void receiveJobs(List<MessageApi.Job> incoming){
        Set<String> active=new HashSet<>();for(var job:incoming)if(!job.status.equals("FAILED"))active.add(jobId(job));
        boolean changed=dismissedJobKeys.removeIf(key->active.contains(key.split("#",2)[0]));
        if(changed)saveDismissals();
        String previous=jobSignature(jobs);jobs.clear();jobs.addAll(incoming);
        if(changed||!previous.equals(jobSignature(jobs)))revision++;
    }
    boolean toolsBusy;
    String toolsStatus="";
    JSONArray contextOperations=new JSONArray();
    private final Map<String,Long> historyRevisions=new HashMap<>();
    java.io.File pendingBackup;
    int pendingBackupConnection, pendingImportConnection;
    String pendingImportAgent="";
    int connectionStamp(){return connectionGeneration;}
    MessageApi searchClient(){return api;}
    void searchFailure(Exception error){if(error instanceof MessageApi.SessionExpired)signedOut(error.getMessage());}
    interface Tool<T>{T run(MessageApi client)throws Exception;}
    <T> void tool(String label,Tool<T> work,java.util.function.Consumer<T> success){
        if(api==null||configuring||toolsBusy)return;
        int connection=connectionGeneration;String room=selectedConversation;MessageApi client=api;
        toolsBusy=true;toolsStatus=label;notifyChanged();
        navigationWorkers.execute(()->{
            try{
                T result=work.run(client);
                main.post(()->{if(connection!=connectionGeneration)return;toolsBusy=false;toolsStatus="";notifyChanged();if(room.equals(selectedConversation))success.accept(result);});
            }catch(Exception failure){main.post(()->{if(connection!=connectionGeneration)return;toolsBusy=false;toolsStatus="";notifyChanged();if(room.equals(selectedConversation))report(failure);});}
        });
    }
    List<MessageApi.Conversation> agentConversations(String agentId){
        List<MessageApi.Conversation> rooms=new ArrayList<>();
        for(var room:conversations)if(room.kind.equals("direct")&&room.agentId.equals(agentId))rooms.add(room);
        return rooms;
    }
    void addConversation(MessageApi.Conversation room){upsertRoom(room);notifyChanged();}
    void replaceConversations(List<MessageApi.Conversation> rooms){conversations.clear();conversations.addAll(rooms);notifyChanged();}
    void clearLocalHistory(String room,long revision){
        scrollPositions.remove(room);historyRevisions.put(room,revision);historyCache.remove(room);
        quoteDrafts.remove(room);if(room.equals(selectedConversation))quotedMessage=null;
        drafts.remove(room);imageDrafts.remove(room);documentDrafts.remove(room);documentEpoch++;preparingDocuments=0;if(room.equals(selectedConversation))draftDocuments.clear();
        pending.removeIf(message->{if(!message.optString("conversationId","shared").equals(room))return false;removeImageFiles(message);return true;});savePending();
        if(room.equals(selectedConversation)){
            generation++;polling=false;messages.clear();jobs.clear();contextOperations=new JSONArray();draft="";draftImages.clear();
            initialLoaded=false;hasOlder=false;loadingOlder=false;this.revision++;notifyChanged();refresh();
        }
    }
    private boolean historyChanged(MessageApi.Page page,String room){
        if(page.historyRevision<0)return false;
        Long previous=historyRevisions.put(room,page.historyRevision);
        if(previous!=null&&previous!=page.historyRevision){clearLocalHistory(room,page.historyRevision);return true;}
        return false;
    }
    String selectedConversation = "shared";
    private int connectionGeneration;
    private final Map<String,String> drafts = new HashMap<>();
    private final Set<String> unconfirmedRooms=new HashSet<>(), creatingRooms=new HashSet<>();
    private final LinkedHashMap<String,RoomSnapshot> historyCache=new LinkedHashMap<>();
    private static final class RoomSnapshot {
        final List<MessageApi.Message> messages;
        final List<MessageApi.Job> jobs;
        final boolean loaded,older;
        RoomSnapshot(ChatSession session){
            int start=Math.max(0,session.messages.size()-300);ScrollPosition position=session.scrollPositions.get(session.selectedConversation);
            if(position!=null&&session.messages.size()>300)for(int i=0;i<session.messages.size();i++)if(session.messages.get(i).id==position.message){start=Math.max(0,Math.min(i-80,session.messages.size()-300));break;}
            messages=new ArrayList<>(session.messages.subList(start,Math.min(session.messages.size(),start+300)));
            jobs=new ArrayList<>(session.jobs);loaded=session.initialLoaded;older=session.hasOlder||start>0;
        }
    }
    boolean openingConversation(){return unconfirmedRooms.contains(selectedConversation);}
    List<JSONObject> currentPending() { List<JSONObject> result=new ArrayList<>();for(JSONObject m:pending)if(m.optString("conversationId","shared").equals(selectedConversation))result.add(m);return result; }
    MessageApi.Conversation selected() { for(MessageApi.Conversation c:conversations)if(c.id.equals(selectedConversation))return c;return null; }
    String title() { return selected()==null?"设备群聊":selected().name; }
    List<MessageApi.Agent> availableAgents() { List<MessageApi.Agent> result=new ArrayList<>();for(MessageApi.Agent a:agents)if(a.enabled&&(selectedConversation.equals("shared")||selectedConversation.startsWith("home:")||selected()!=null&&selected().agentIds.contains(a.id)))result.add(a);return result; }
    void select(String id) {
        if(id.equals(selectedConversation))return;
        historyCache.remove(selectedConversation);historyCache.put(selectedConversation,new RoomSnapshot(this));
        while(historyCache.size()>8){String evicted=historyCache.keySet().iterator().next();historyCache.remove(evicted);scrollPositions.remove(evicted);}
        quoteDrafts.put(selectedConversation,quotedMessage);
        documentDrafts.put(selectedConversation,new ArrayList<>(draftDocuments));drafts.put(selectedConversation,draft);imageDrafts.put(selectedConversation,new ArrayList<>(draftImages));selectedConversation=id;quotedMessage=quoteDrafts.get(id);draft=drafts.getOrDefault(id,"");
        draftImages.clear();draftImages.addAll(imageDrafts.getOrDefault(id,List.of()));draftDocuments.clear();draftDocuments.addAll(documentDrafts.getOrDefault(id,List.of()));
        generation++;polling=false;loadingOlder=false;messages.clear();jobs.clear();contextOperations=new JSONArray();
        RoomSnapshot cached=historyCache.get(id);initialLoaded=cached!=null&&cached.loaded;hasOlder=cached!=null&&cached.older;
        if(cached!=null){messages.addAll(cached.messages);jobs.addAll(cached.jobs);}
        revision++;notifyChanged();refresh();
    }
    void mention(MessageApi.Agent agent) { draft+=(draft.isEmpty()||Character.isWhitespace(draft.charAt(draft.length()-1))?"":" ")+"@"+agent.handle+" ";notifyChanged(); }
    void openDirect(MessageApi.Agent agent) {
        String primary=user==null||user.home().equals("shared")?"direct:"+agent.id:"dm:"+user.id()+":"+agent.id;
        MessageApi.Conversation known=null;
        for(var room:conversations){
            if(!room.kind.equals("direct")||!room.agentId.equals(agent.id))continue;
            if(room.id.equals(primary)){known=room;break;}
            if(known==null)known=room;
        }
        if(known!=null&&!unconfirmedRooms.contains(known.id)){select(known.id);return;}
        if(api==null||configuring)return;
        String roomId=known==null?primary:known.id;
        if(known==null)try{conversations.add(new MessageApi.Conversation(new JSONObject().put("id",roomId).put("name",agent.name).put("kind","direct").put("agentId",agent.id).put("agentIds",new JSONArray(List.of(agent.id)))));}catch(JSONException failure){report(failure);return;}
        unconfirmedRooms.add(roomId);select(roomId);status="正在打开私聊…";notifyChanged();
        if(!creatingRooms.add(roomId))return;
        int connection=connectionGeneration;MessageApi client=api;
        navigationWorkers.execute(()->{
            try{
                MessageApi.Conversation room=client.direct(agent.id);
                main.post(()->{
                    if(connection!=connectionGeneration)return;creatingRooms.remove(roomId);unconfirmedRooms.remove(roomId);upsertRoom(room);
                    if(selectedConversation.equals(roomId)){if(!room.id.equals(roomId)){conversations.removeIf(old->old.id.equals(roomId));select(room.id);}status="正在同步…";revision++;notifyChanged();refresh();}
                    else notifyChanged();
                });
            }catch(Exception failure){main.post(()->{if(connection!=connectionGeneration)return;creatingRooms.remove(roomId);if(selectedConversation.equals(roomId)){status="会话打开失败，请返回列表后重试";revision++;notifyChanged();report(failure);}});}
        });
    }
    void createGroup(String name,List<String> ids,List<String> usernames,java.util.function.Consumer<MessageApi.Conversation> created){
        if(api==null||configuring)return;int connection=connectionGeneration;MessageApi client=api;
        navigationWorkers.execute(()->{try{
            var room=client.group(name,ids,usernames);main.post(()->{if(connection!=connectionGeneration)return;upsertRoom(room);notifyChanged();created.accept(room);});
        }catch(Exception failure){main.post(()->{if(connection==connectionGeneration)report(failure);});}});
    }
    private void upsertRoom(MessageApi.Conversation room){conversations.removeIf(existing->existing.id.equals(room.id));conversations.add(room);}
    void retryJob(MessageApi.Job job) {
        if(api==null)return;MessageApi client=api;
        worker.execute(()->{try{client.retryJob(job);main.post(this::refresh);}catch(Exception e){main.post(()->report(e));}});
    }
    final List<JSONObject> pending = new ArrayList<>();
    final Set<String> sending = new HashSet<>();
    Listener listener;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final ExecutorService navigationWorkers=Executors.newFixedThreadPool(2);
    private final ExecutorService directoryWorker=Executors.newSingleThreadExecutor();
    private boolean directoryLoading;
    private long lastDirectoryRefresh;
    private final ExecutorService avatarWorkers=Executors.newFixedThreadPool(2);
    private final android.util.LruCache<String,android.graphics.Bitmap> avatarCache=new android.util.LruCache<String,android.graphics.Bitmap>(4096) {
        @Override protected int sizeOf(String key,android.graphics.Bitmap bitmap){return Math.max(1,bitmap.getAllocationByteCount()/1024);}
    };
    private final Map<String,List<java.lang.ref.WeakReference<android.widget.ImageView>>> avatarWaiters=new HashMap<>();
    String avatarFor(String agentId){for(MessageApi.Agent a:agents)if(a.id.equals(agentId))return a.avatarId;return "alfred";}
    void bindAvatar(android.widget.ImageView view,String avatarId){
        String id=avatarId==null?"alfred":avatarId;int connection=connectionGeneration;String key=connection+":"+id;
        view.setTag(key);view.setImageResource(R.drawable.ic_agent_placeholder);
        android.graphics.Bitmap cached=avatarCache.get(key);if(cached!=null){view.setImageBitmap(cached);return;}
        if(api==null||avatarWorkers.isShutdown())return;
        var waiter=new java.lang.ref.WeakReference<>(view);
        if(avatarWaiters.containsKey(key)){avatarWaiters.get(key).add(waiter);return;}
        List<java.lang.ref.WeakReference<android.widget.ImageView>> waiting=new ArrayList<>();waiting.add(waiter);avatarWaiters.put(key,waiting);
        MessageApi client=api;
        avatarWorkers.execute(()->{
            android.graphics.Bitmap bitmap=null;
            try{
                byte[] bytes=client.avatar(id);var options=new android.graphics.BitmapFactory.Options();options.inJustDecodeBounds=true;
                android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);int sample=1;
                while(options.outWidth/sample>256||options.outHeight/sample>256)sample*=2;
                options.inJustDecodeBounds=false;options.inSampleSize=sample;bitmap=android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);
            }catch(Exception ignored){}
            final android.graphics.Bitmap result=bitmap;
            main.post(()->{
                var views=avatarWaiters.remove(key);if(connection!=connectionGeneration||result==null)return;
                avatarCache.put(key,result);if(views!=null)for(var reference:views){var target=reference.get();if(target!=null&&key.equals(target.getTag()))target.setImageBitmap(result);}
            });
        });
    }
    private final Handler main = new Handler(Looper.getMainLooper());
    private MessageApi api;
    private String pendingKey;
    private int generation, backoff = 2000;
    private boolean polling;
    private final Runnable tick = this::poll;

    ChatSession(Context context) {
        files=context.getFilesDir();resolver=context.getContentResolver();
        prefs = context.getSharedPreferences("connection", Context.MODE_PRIVATE);
        secrets = new SecretStore(context);
        deviceId = prefs.getString("deviceId", UUID.randomUUID().toString());
        prefs.edit().putString("deviceId", deviceId).apply();
        server = prefs.getString("server", "https://121.40.254.112");
        sender = prefs.getString("sender", android.os.Build.MODEL);
        try {
            String token = secrets.read();
            String userId=prefs.getString("chatUserId","");
            if(!userId.isEmpty()&&token.startsWith("chat_")){
                user=new MessageApi.User(userId,sender);
                selectedConversation=user.home();
                api=new MessageApi(Endpoint.normalize(server),token);
                restorePending(user.id());
            }
        } catch (Exception e) { status = "无法读取连接设置，请重新连接。"; }
    }
    boolean configured() { return api != null; }
    String legacyServiceToken(String address){
        try{
            if(user==null&&Endpoint.normalize(address).equals(Endpoint.normalize(server))){
                String saved=secrets.read();
                if(!saved.startsWith("chat_"))return saved;
            }
        }catch(Exception ignored){}
        return "";
    }
    boolean owns(MessageApi.Conversation room){
        return room!=null&&user!=null&&(user.id().equals(room.ownerId)||room.ownerId.isEmpty()&&user.home().equals("shared"));
    }
    boolean managesGroup(MessageApi.Conversation room){
        return room!=null&&room.kind.equals("group")&&!room.id.equals("shared")&&!room.id.startsWith("home:")&&owns(room);
    }
    boolean mine(MessageApi.Message message){
        if(!message.role.equals("user"))return false;
        return user==null?message.deviceId.equals(deviceId):user.id().equals(message.userId);
    }
    void notifyChanged() { if (listener != null) listener.changed(); }
    void report(Exception e) { if (listener != null) listener.error(e.getMessage() == null ? "操作未完成，请重试。" : e.getMessage()); }
    void start() { active = true; refresh(); }
    void stop() { active = false; main.removeCallbacks(tick); connected = false; status = "已暂停 · 返回后自动同步"; }
    void close() { stop(); listener = null; worker.shutdownNow();navigationWorkers.shutdownNow();directoryWorker.shutdownNow();usageWorker.shutdownNow(); avatarWorkers.shutdownNow();avatarWaiters.clear();avatarCache.evictAll();imageLoader.close(); }
    void refresh() { main.removeCallbacks(tick); if (active && api != null) main.post(tick); }

    void login(String address,String serviceToken,String username,Runnable success){
        if(configuring||api!=null)return;
        final String normalized, name=username.trim();
        String credential=serviceToken.trim();
        if(credential.isEmpty())credential=legacyServiceToken(address);
        final String token=credential;
        try{
            normalized=Endpoint.normalize(address);
            if(token.isEmpty()||token.length()>900||token.chars().anyMatch(c->Character.isWhitespace(c)||Character.isISOControl(c))
                    ||name.isEmpty()||name.length()>60||name.chars().anyMatch(Character::isISOControl))
                throw new IllegalArgumentException("请填写服务访问令牌和 1–60 字的 UserName。");
        }catch(Exception error){report(error);return;}
        configuring=true;
        notifyChanged();
        worker.execute(()->{
            try{
                MessageApi.Login login=new MessageApi(normalized,token).login(name);
                MessageApi candidate=new MessageApi(normalized,login.sessionToken());
                try{
                    secrets.saveSession(login.sessionToken(),normalized,login.user());
                }catch(Exception error){
                    try{candidate.logout();}catch(Exception ignored){}
                    throw error;
                }
                main.post(()->{
                    resetAccount();
                    user=login.user();
                    api=candidate;
                    server=normalized;
                    sender=user.username();
                    selectedConversation=user.home();
                    restorePending(user.id());
                    configuring=false;
                    status="正在同步…";
                    notifyChanged();
                    success.run();
                    refresh();
                });
            }catch(Exception error){
                main.post(()->{configuring=false;notifyChanged();report(error);});
            }
        });
    }

    void logout(){
        if(api==null||configuring)return;
        if(toolsBusy||!sending.isEmpty()){
            report(new java.io.IOException("请等待当前聊天操作完成后退出。"));
            return;
        }
        configuring=true;
        MessageApi client=api;
        notifyChanged();
        worker.execute(()->{
            try{
                client.logout();
            }catch(MessageApi.SessionExpired alreadySignedOut){
                // The server has already rejected this session.
            }catch(Exception error){
                main.post(()->{configuring=false;notifyChanged();report(error);refresh();});
                return;
            }
            main.post(()->signedOut("已退出登录"));
        });
    }

    private void signedOut(String message){
        secrets.clearSession();
        resetAccount();
        configuring=false;
        status=message;
        notifyChanged();
    }

    private void resetAccount(){
        generation++;
        connectionGeneration++;
        api=null;
        user=null;
        connected=false;
        polling=false;
        initialLoaded=false;
        hasOlder=false;
        loadingOlder=false;
        toolsBusy=false;
        toolsStatus="";
        directoryLoading=false;
        lastDirectoryRefresh=0;
        selectedConversation="shared";
        avatarCache.evictAll();
        avatarWaiters.clear();
        historyCache.clear();scrollPositions.clear();
        historyRevisions.clear();
        unconfirmedRooms.clear();
        creatingRooms.clear();
        conversations.clear();
        agents.clear();
        messages.clear();
        jobs.clear();
        contextOperations=new JSONArray();
        draft="";
        quotedMessage=null;quoteDrafts.clear();favoriteRequests.clear();
        drafts.clear();
        documentEpoch++;preparingDocuments=0;documentDrafts.clear();draftDocuments.clear();documentPickerRoom="";
        imageDrafts.clear();
        draftImages.clear();
        pending.clear();
        pendingKey=null;
        dismissedJobKeys.clear();
        modelUsage.clear();
        usageBusy=false;
        usageLoadedAt=0;
        usageError="";
        if(pendingBackup!=null)pendingBackup.delete();
        pendingBackup=null;
        pendingImportAgent="";
        revision++;
    }

    private void poll() {
        if (!active || api == null || polling || configuring) return;
        refreshDirectory();
        if(openingConversation())return;
        polling = true;
        int epoch = generation;
        MessageApi client = api;
        String conversation = selectedConversation;
        Long after = initialLoaded ? (messages.isEmpty() ? 0L : messages.get(messages.size() - 1).id) : null;
        worker.execute(() -> {
            try {
                MessageApi.Page page = client.page(conversation, after, null);
                main.post(() -> {
                    if (epoch != generation) return;
                    polling = false;
                    if(historyChanged(page,conversation)){schedule(0);return;}
                    String previousOperations=contextOperations.toString();contextOperations=page.contextOperations;if(!previousOperations.equals(contextOperations.toString()))revision++;
                    receiveJobs(page.jobs);
                    if (!initialLoaded) { hasOlder = page.hasMore; initialLoaded = true; }
                    merge(page.messages); if(!connected)revision++; connected = true; backoff = 2000; status = "已连接 · 自动同步";
                    notifyChanged(); schedule(after != null && page.hasMore ? 0 : backoff);
                });
            } catch (Exception e) {
                main.post(() -> {
                    if (epoch != generation) return;
                    if(e instanceof MessageApi.SessionExpired){
                        signedOut(e.getMessage());
                        return;
                    }
                    polling = false; connected = false; status = e.getMessage() == null ? "连接未完成" : e.getMessage();
                    backoff = Math.min(backoff * 2, 30000); notifyChanged(); schedule(backoff);
                });
            }
        });
    }
    private void refreshDirectory(){
        if(directoryLoading||api==null||directoryWorker.isShutdown()||(lastDirectoryRefresh!=0&&android.os.SystemClock.elapsedRealtime()-lastDirectoryRefresh<10_000))return;
        directoryLoading=true;lastDirectoryRefresh=android.os.SystemClock.elapsedRealtime();int connection=connectionGeneration;MessageApi client=api;String deviceName=sender;
        directoryWorker.execute(()->{
            try{
                var directory=client.agents();var rooms=client.conversations();
                main.post(()->{if(connection!=connectionGeneration)return;
                    String old=avatarSignature(agents);agents.clear();agents.addAll(directory);if(!old.equals(avatarSignature(agents)))revision++;
                    for(var room:conversations)if(unconfirmedRooms.contains(room.id)&&rooms.stream().noneMatch(known->known.id.equals(room.id)))rooms.add(room);
                    conversations.clear();conversations.addAll(rooms);notifyChanged();
                });
                try{client.heartbeat(deviceId,deviceName);}catch(Exception ignored){}
            }catch(Exception ignored){}
            finally{main.post(()->{if(connection==connectionGeneration)directoryLoading=false;});}
        });
    }
    private void schedule(int delay) { main.removeCallbacks(tick); if (active) main.postDelayed(tick, delay); }

    void older() {
        if (loadingOlder || !hasOlder || messages.isEmpty() || api == null) return;
        loadingOlder = true; notifyChanged();
        long before = messages.get(0).id;
        int epoch = generation; MessageApi client = api; String conversation=selectedConversation;
        worker.execute(() -> {
            try {
                MessageApi.Page page = client.page(conversation, null, before);
                main.post(() -> {
                    if (epoch != generation) return;
                    loadingOlder = false;if(historyChanged(page,conversation))return;hasOlder = page.hasMore; merge(page.messages); notifyChanged();
                });
            } catch (Exception e) { main.post(() -> { if (epoch == generation) { loadingOlder = false; notifyChanged(); report(e); } }); }
        });
    }

    boolean sendDraft(String text) {
        text = text.trim();
        if (!canSend(text)) return false;
        try {
            JSONArray docIds=new JSONArray(),docs=new JSONArray();for(var doc:draftDocuments){doc.save(files,pendingKey);docIds.put(doc.id);docs.put(doc.json());}
            JSONArray imageIds=new JSONArray();
            for(ChatImage image:draftImages){image.save(files,pendingKey);imageIds.put(image.id);}
            JSONObject message = new JSONObject().put("clientMessageId", UUID.randomUUID().toString()).put("deviceId", deviceId)
                    .put("sender", sender).put("platform", "android").put("text", text).put("conversationId",selectedConversation).put("mentionAgentIds",new JSONArray());
            if(quotedMessage!=null)message.put("quoteMessageId",quotedMessage.id).put("quote",quotedMessage.json);
            message.put("imageIds",imageIds).put("documentIds",docIds).put("documents",docs);pending.add(message);
            if (!savePending()) { pending.remove(message); throw new java.io.IOException("无法保存待发消息，请检查设备存储后重试。"); }
            quotedMessage=null;quoteDrafts.remove(selectedConversation);
            draft = "";draftImages.clear();imageDrafts.remove(selectedConversation);draftDocuments.clear();documentDrafts.remove(selectedConversation); revision++; retry(message); return true;
        } catch (Exception e) { report(e); return false; }
    }
    void retry(JSONObject message) {
        String id = message.optString("clientMessageId");
        if (api == null || configuring || sending.contains(id)) return;
        sending.add(id); revision++; notifyChanged();
        int epoch = connectionGeneration; MessageApi client = api;
        worker.execute(() -> {
            try {
                for(var doc:documents(message)){byte[] bytes=ChatDocument.local(files,pendingKey,doc.id);client.uploadDocument(doc,message.optString("conversationId","shared"),bytes);}
                for(String imageId:imageIds(message)){
                    byte[] data=ChatImage.local(files,pendingKey,imageId);
                    if(data!=null)client.uploadImage(imageId,message.optString("conversationId","shared"),data);
                }
                client.send(message);
                main.post(() -> {
                    if (epoch != connectionGeneration) return;
                    sending.remove(id); pending.remove(message); savePending();removeImageFiles(message); revision++; notifyChanged(); refresh();
                });
            } catch (Exception e) {
                main.post(() -> {
                    if (epoch != connectionGeneration) return;
                    sending.remove(id); revision++; notifyChanged(); report(e);
                });
            }
        });
    }

    private String avatarSignature(List<MessageApi.Agent> directory){StringBuilder signature=new StringBuilder();for(MessageApi.Agent a:directory)signature.append(a.id).append(a.avatarId);return signature.toString();}
    private String jobSignature(List<MessageApi.Job> jobs) { StringBuilder signature=new StringBuilder();for(MessageApi.Job job:jobs)signature.append(job.signature());return signature.toString(); }
    private void merge(List<MessageApi.Message> incoming) {
        TreeMap<Long, MessageApi.Message> unique = new TreeMap<>();
        for (MessageApi.Message m : messages) unique.put(m.id, m);
        for (MessageApi.Message m : incoming) unique.put(m.id, m);
        if (unique.size() != messages.size()) { messages.clear(); messages.addAll(unique.values()); revision++; }
        reconcile();
    }
    private void reconcile() {
        Set<String> confirmed = new HashSet<>();
        for (MessageApi.Message m : messages) if (m.deviceId.equals(deviceId)) confirmed.add(m.clientMessageId);
        if (pending.removeIf(m -> {if(!confirmed.contains(m.optString("clientMessageId")))return false;removeImageFiles(m);return true;})) { revision++; savePending(); }
    }
    private void restorePending(String token) {
        pending.clear();dismissedJobKeys.clear();
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256").digest((server + "\n" + token).getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(); for (byte b : hash) hex.append(String.format(Locale.ROOT, "%02x", b));
            pendingKey = "outbox." + hex;
            dismissedJobKeys.addAll(prefs.getStringSet(pendingKey+".dismissedJobs",Collections.emptySet()));
            JSONArray array = new JSONArray(prefs.getString(pendingKey, "[]"));
            for (int i = 0; i < array.length(); i++) pending.add(array.getJSONObject(i));
        } catch (Exception e) { status = "待发消息读取失败。"; }
    }
    private boolean savePending() {
        if (pendingKey == null) return false;
        JSONArray array = new JSONArray(); for (JSONObject m : pending) array.put(m);
        return prefs.edit().putString(pendingKey, array.toString()).commit();
    }
}
