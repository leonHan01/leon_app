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
    final SharedPreferences prefs;
    final SecretStore secrets;
    final String deviceId;
    String server, sender, status = "尚未连接", draft = "";
    final List<ChatImage> draftImages = new ArrayList<>();
    private final Map<String,List<ChatImage>> imageDrafts = new HashMap<>();
    private final java.io.File files;
    private final android.content.ContentResolver resolver;
    private final ChatImageLoader imageLoader = new ChatImageLoader();
    void refreshImages(){imageLoader.refresh();}
    void bindImage(android.widget.ImageView view,String id){bindImage(view,id,false);}
    void bindImage(android.widget.ImageView view,String id,boolean large){
        MessageApi client=api;String scope=pendingKey;int connection=connectionGeneration;
        imageLoader.bind(view,connection+":"+id,()->{
            byte[] local=ChatImage.local(files,scope,id);if(local!=null)return local;
            if(client==null)throw new java.io.IOException("请先连接服务器");return client.image(id);
        },large);
    }
    static List<String> imageIds(JSONObject message){
        var ids=message.optJSONArray("imageIds");var result=new ArrayList<String>();
        if(ids!=null)for(int i=0;i<ids.length();i++)result.add(ids.optString(i));return result;
    }
    private void removeImageFiles(JSONObject message){for(String id:imageIds(message))ChatImage.remove(files,pendingKey,id);}
    int preparingImages;
    boolean canSend(String text) { return configured() && !configuring && preparingImages==0 && (!text.trim().isEmpty() || !draftImages.isEmpty()) && text.length()<=8000; }
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
    final List<MessageApi.Conversation> conversations = new ArrayList<>();
    final List<MessageApi.Job> jobs = new ArrayList<>();
    String selectedConversation = "shared";
    private int connectionGeneration;
    private int pollCycle;
    private final Map<String,String> drafts = new HashMap<>();
    List<JSONObject> currentPending() { List<JSONObject> result=new ArrayList<>();for(JSONObject m:pending)if(m.optString("conversationId","shared").equals(selectedConversation))result.add(m);return result; }
    MessageApi.Conversation selected() { for(MessageApi.Conversation c:conversations)if(c.id.equals(selectedConversation))return c;return null; }
    String title() { return selected()==null?"设备群聊":selected().name; }
    List<MessageApi.Agent> availableAgents() { List<MessageApi.Agent> result=new ArrayList<>();for(MessageApi.Agent a:agents)if(a.enabled&&(selectedConversation.equals("shared")||selected()!=null&&selected().agentIds.contains(a.id)))result.add(a);return result; }
    void select(String id) {
        if(id.equals(selectedConversation))return;
        drafts.put(selectedConversation,draft);imageDrafts.put(selectedConversation,new ArrayList<>(draftImages));selectedConversation=id;draft=drafts.getOrDefault(id,"");
        draftImages.clear();draftImages.addAll(imageDrafts.getOrDefault(id,List.of()));
        generation++;polling=false;initialLoaded=false;loadingOlder=false;hasOlder=false;messages.clear();jobs.clear();revision++;notifyChanged();refresh();
    }
    void mention(MessageApi.Agent agent) { draft+=(draft.isEmpty()||Character.isWhitespace(draft.charAt(draft.length()-1))?"":" ")+"@"+agent.handle+" ";notifyChanged(); }
    void openDirect(MessageApi.Agent agent) { roomAction(agent.id,null,null); }
    void group(String name,List<String> ids) { roomAction(null,name,ids); }
    private void roomAction(String agentId,String name,List<String> ids) {
        if(api==null||configuring)return;int connection=connectionGeneration;MessageApi client=api;
        worker.execute(()->{try {
            MessageApi.Conversation room=agentId!=null?client.direct(agentId):client.group(name,ids);
            List<MessageApi.Conversation> directory=client.conversations();
            main.post(()->{if(connection!=connectionGeneration)return;conversations.clear();conversations.addAll(directory);select(room.id);notifyChanged();});
        }catch(Exception e){main.post(()->{if(connection==connectionGeneration)report(e);});}});
    }
    void retryJob(MessageApi.Job job) {
        if(api==null)return;MessageApi client=api;
        worker.execute(()->{try{client.retryJob(job);main.post(this::refresh);}catch(Exception e){main.post(()->report(e));}});
    }
    final List<JSONObject> pending = new ArrayList<>();
    final Set<String> sending = new HashSet<>();
    Listener listener;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final ExecutorService avatarWorkers=Executors.newFixedThreadPool(2);
    private final android.util.LruCache<String,android.graphics.Bitmap> avatarCache=new android.util.LruCache<String,android.graphics.Bitmap>(4096) {
        @Override protected int sizeOf(String key,android.graphics.Bitmap bitmap){return Math.max(1,bitmap.getAllocationByteCount()/1024);}
    };
    private final Map<String,List<java.lang.ref.WeakReference<android.widget.ImageView>>> avatarWaiters=new HashMap<>();
    String avatarFor(String agentId){for(MessageApi.Agent a:agents)if(a.id.equals(agentId))return a.avatarId;return "alfred";}
    void bindAvatar(android.widget.ImageView view,String avatarId){
        String id=avatarId==null?"alfred":avatarId;int connection=connectionGeneration;String key=connection+":"+id;
        view.setTag(key);view.setImageResource(android.R.drawable.ic_menu_myplaces);
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
            if (!token.isEmpty()) { api = new MessageApi(Endpoint.normalize(server), token); restorePending(token); }
        } catch (Exception e) { status = "无法读取连接设置，请重新连接。"; }
    }
    boolean configured() { return api != null; }
    String token() { try { return secrets.read(); } catch (Exception e) { return ""; } }
    void notifyChanged() { if (listener != null) listener.changed(); }
    void report(Exception e) { if (listener != null) listener.error(e.getMessage() == null ? "操作未完成，请重试。" : e.getMessage()); }
    void start() { active = true; refresh(); }
    void stop() { active = false; main.removeCallbacks(tick); connected = false; status = "已暂停 · 返回后自动同步"; }
    void close() { stop(); listener = null; worker.shutdownNow(); avatarWorkers.shutdownNow();avatarWaiters.clear();avatarCache.evictAll();imageLoader.close(); }
    void refresh() { main.removeCallbacks(tick); if (active && api != null) main.post(tick); }

    void configure(String address, String token, String name, Runnable success) {
        if (configuring) return;
        final String normalized, cleanToken = token.trim(), cleanName = name.trim();
        try {
            normalized = Endpoint.normalize(address);
            if (cleanToken.isEmpty() || cleanToken.length() > 900 || cleanToken.chars().anyMatch(c -> Character.isWhitespace(c) || Character.isISOControl(c))
                    || cleanName.isEmpty() || cleanName.length() > 60 || cleanName.chars().anyMatch(Character::isISOControl))
                throw new IllegalArgumentException("请填写访问令牌和 1–60 字的设备名称。");
            if (!sending.isEmpty()) throw new IllegalArgumentException("请等待正在发送的消息完成，再切换连接。");
        } catch (Exception e) { report(e); return; }
        configuring = true; notifyChanged();
        worker.execute(() -> {
            try {
                MessageApi candidate = new MessageApi(normalized, cleanToken);
                MessageApi.Page page = candidate.page("shared", null, null);
                List<MessageApi.Agent> directory=candidate.agents(); List<MessageApi.Conversation> rooms=candidate.conversations();
                secrets.save(cleanToken, normalized, cleanName);
                main.post(() -> {
                    generation++; connectionGeneration++; avatarCache.evictAll();avatarWaiters.clear(); selectedConversation="shared";drafts.clear();agents.clear();agents.addAll(directory);conversations.clear();conversations.addAll(rooms);jobs.clear();jobs.addAll(page.jobs);polling = false; loadingOlder = false; api = candidate; server = normalized; sender = cleanName;
                    messages.clear(); messages.addAll(page.messages); initialLoaded = true; hasOlder = page.hasMore;
                    restorePending(cleanToken); reconcile();
                    connected = true; configuring = false; status = "已连接 · 自动同步"; draft = "";draftImages.clear();imageDrafts.clear();
                    revision++; notifyChanged(); success.run(); refresh();
                });
            } catch (Exception e) { main.post(() -> { configuring = false; notifyChanged(); report(e); refresh(); }); }
        });
    }

    private void poll() {
        if (!active || api == null || polling || configuring) return;
        polling = true;
        int epoch = generation;
        MessageApi client = api;
        String conversation = selectedConversation; boolean directoryDue = pollCycle++ % 5 == 0;
        String deviceName = sender;
        Long after = initialLoaded ? (messages.isEmpty() ? 0L : messages.get(messages.size() - 1).id) : null;
        worker.execute(() -> {
            try {
                MessageApi.Page page = client.page(conversation, after, null);
                List<MessageApi.Agent> directory=directoryDue?client.agents():null;
                List<MessageApi.Conversation> rooms=directoryDue?client.conversations():null;
                if (directoryDue) try { client.heartbeat(deviceId,deviceName); } catch (Exception ignored) { /* Presence must not interrupt message delivery. */ }
                main.post(() -> {
                    if (epoch != generation) return;
                    polling = false;
                    if(directory!=null){String oldAvatars=avatarSignature(agents);agents.clear();agents.addAll(directory);if(!oldAvatars.equals(avatarSignature(agents)))revision++;conversations.clear();conversations.addAll(rooms);}
                    String previousSignature=jobSignature(jobs);jobs.clear();jobs.addAll(page.jobs);if(!previousSignature.equals(jobSignature(jobs)))revision++;
                    if (!initialLoaded) { hasOlder = page.hasMore; initialLoaded = true; }
                    merge(page.messages); if(!connected)revision++; connected = true; backoff = 2000; status = "已连接 · 自动同步";
                    notifyChanged(); schedule(after != null && page.hasMore ? 0 : backoff);
                });
            } catch (Exception e) {
                main.post(() -> {
                    if (epoch != generation) return;
                    polling = false; connected = false; status = e.getMessage() == null ? "连接未完成" : e.getMessage();
                    backoff = Math.min(backoff * 2, 30000); notifyChanged(); schedule(backoff);
                });
            }
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
                    loadingOlder = false; hasOlder = page.hasMore; merge(page.messages); notifyChanged();
                });
            } catch (Exception e) { main.post(() -> { if (epoch == generation) { loadingOlder = false; notifyChanged(); report(e); } }); }
        });
    }

    boolean sendDraft(String text) {
        text = text.trim();
        if (!canSend(text)) return false;
        try {
            JSONArray imageIds=new JSONArray();
            for(ChatImage image:draftImages){image.save(files,pendingKey);imageIds.put(image.id);}
            JSONObject message = new JSONObject().put("clientMessageId", UUID.randomUUID().toString()).put("deviceId", deviceId)
                    .put("sender", sender).put("platform", "android").put("text", text).put("conversationId",selectedConversation).put("mentionAgentIds",new JSONArray());
            message.put("imageIds",imageIds);pending.add(message);
            if (!savePending()) { pending.remove(message); throw new java.io.IOException("无法保存待发消息，请检查设备存储后重试。"); }
            draft = "";draftImages.clear();imageDrafts.remove(selectedConversation); revision++; retry(message); return true;
        } catch (Exception e) { report(e); return false; }
    }
    void retry(JSONObject message) {
        String id = message.optString("clientMessageId");
        if (api == null || configuring || sending.contains(id)) return;
        sending.add(id); revision++; notifyChanged();
        int epoch = connectionGeneration; MessageApi client = api;
        worker.execute(() -> {
            try {
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
        pending.clear();
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256").digest((server + "\n" + token).getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(); for (byte b : hash) hex.append(String.format(Locale.ROOT, "%02x", b));
            pendingKey = "outbox." + hex;
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
