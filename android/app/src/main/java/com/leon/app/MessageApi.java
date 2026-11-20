package com.leon.app;

import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class MessageApi {
    final String base;
    private final String token;
    MessageApi(String base, String token) { this.base = base; this.token = token; }

    record User(String id,String username) {
        User(JSONObject json)throws JSONException{this(json.getString("id"),json.getString("username"));}
        String home(){return username.equalsIgnoreCase("Leon")?"shared":"home:"+id;}
    }
    record Login(User user,String sessionToken) {}
    static final class SessionExpired extends IOException {
        SessionExpired(){super("登录已失效，请重新登录。");}
    }
    Login login(String username)throws Exception{
        var result=request("/api/conversations/account/login",new JSONObject().put("username",username));
        return new Login(new User(result.getJSONObject("user")),result.getString("sessionToken"));
    }
    void logout()throws Exception{request("/api/conversations/account/logout",new JSONObject());}

    static final class Message {
        final long id, createdAt;
        final String clientMessageId, deviceId, sender, platform, text, conversationId, role, agentId, userId;
        final List<String> imageIds = new ArrayList<>();
        final Quote quote;final List<ChatDocument> documents;
        Message(JSONObject json) throws JSONException {
            documents=ChatDocument.parse(json.optJSONArray("documents"));
            quote=json.isNull("quote")?null:json.has("quote")?new Quote(json.getJSONObject("quote")):null;
            id = json.getLong("id"); createdAt = json.getLong("createdAt");
            clientMessageId = json.getString("clientMessageId"); deviceId = json.getString("deviceId");
            sender = json.getString("sender"); platform = json.getString("platform"); text = json.getString("text");
            conversationId = json.optString("conversationId", "shared"); role = json.optString("role", "user"); agentId = json.optString("agentId", "");
            userId=json.isNull("userId")?"":json.optString("userId");
            JSONArray images=json.optJSONArray("images");if(images!=null)for(int i=0;i<images.length();i++)imageIds.add(images.getJSONObject(i).getString("id"));
        }
    }
    static final class Quote {
        final long id;final String sender,text;final JSONObject json;
        Quote(JSONObject value)throws JSONException{json=value;id=value.getLong("id");sender=value.getString("sender");text=value.getString("text");}
        Quote(Message message)throws JSONException{
            id=message.id;sender=message.sender;text=message.text;JSONArray images=new JSONArray();for(String image:message.imageIds)images.put(new JSONObject().put("id",image));
            json=new JSONObject().put("documents",new JSONArray(message.documents.stream().map(d->{try{return d.json();}catch(Exception e){throw new IllegalStateException(e);}}).collect(java.util.stream.Collectors.toList()))).put("id",id).put("sender",sender).put("text",text).put("images",images);
        }
        String preview(){return (json.optJSONArray("images")!=null&&json.optJSONArray("images").length()>0?"[图片] ":"")+(json.optJSONArray("documents")!=null&&json.optJSONArray("documents").length()>0?"[文件] ":"")+text.replace('\n',' ');}
    }
    static final class Favorite {
        final long id,savedAt;final Message message;final String conversationName;
        Favorite(JSONObject value)throws JSONException{id=value.getLong("id");savedAt=value.getLong("savedAt");message=new Message(value.getJSONObject("message"));conversationName=value.getString("conversationName");}
    }
    static final class FavoritePage {
        final List<Favorite> results=new ArrayList<>();final boolean hasMore;final Long nextBefore;
        FavoritePage(JSONObject value)throws JSONException{var rows=value.getJSONArray("results");for(int i=0;i<rows.length();i++)results.add(new Favorite(rows.getJSONObject(i)));hasMore=value.getBoolean("hasMore");nextBefore=value.isNull("nextBefore")?null:value.getLong("nextBefore");}
    }
    Favorite addFavorite(long message)throws Exception{return new Favorite(request("/api/device-messages/"+message+"/favorite",new JSONObject()));}
    FavoritePage favorites(String query,Long before)throws Exception{return new FavoritePage(request("/api/device-messages/favorites?q="+encode(query)+(before==null?"":"&before="+before),null));}
    void removeFavorite(long id)throws Exception{request("/api/device-messages/favorites/"+id+"/remove",new JSONObject());}
    byte[] favoriteImage(long favorite,String image)throws Exception{
        if(!image.matches("[a-fA-F0-9-]{36}"))throw new IOException("图片标识无效");
        return requestBytes("/api/device-messages/favorites/"+favorite+"/images/"+image,null,"application/json",1024*1024);
    }
    static final class Agent {
        final String id, name, handle, provider, model, description, avatarId; final boolean enabled;
        Agent(JSONObject j) throws JSONException { id=j.getString("id");name=j.getString("name");handle=j.getString("handle");provider=j.getString("provider");model=j.isNull("model")?"":j.optString("model");description=j.isNull("description")?"":j.optString("description");enabled=j.getBoolean("enabled");avatarId=j.optString("avatarId","alfred"); }
    }
    static final class Conversation {
        final String id,name,kind,agentId,ownerId; final List<String> agentIds=new ArrayList<>();
        Conversation(JSONObject j) throws JSONException { id=j.getString("id");name=j.getString("name");kind=j.getString("kind");agentId=j.optString("agentId","");ownerId=j.isNull("ownerId")?"":j.optString("ownerId");JSONArray ids=j.getJSONArray("agentIds");for(int i=0;i<ids.length();i++)agentIds.add(ids.getString(i)); }
    }
    static final class ModelUsage {
        final String provider,model;
        final long inputTokens,outputTokens,totalTokens,reportedCalls,unreportedCalls;
        ModelUsage(JSONObject json) throws JSONException {
            provider=json.getString("provider");model=json.getString("model");
            inputTokens=json.getLong("inputTokens");outputTokens=json.getLong("outputTokens");totalTokens=json.getLong("totalTokens");
            reportedCalls=json.getLong("reportedCalls");unreportedCalls=json.getLong("unreportedCalls");
        }
    }
    List<ModelUsage> usage() throws Exception {
        JSONArray rows=new JSONArray(requestText("/api/agents/usage",null));List<ModelUsage> result=new ArrayList<>();
        for(int i=0;i<rows.length();i++)result.add(new ModelUsage(rows.getJSONObject(i)));return result;
    }
    static final class Job {
        final long messageId; final String agentId,agentName,status,error,userId;
        Job(JSONObject j) throws JSONException { messageId=j.getLong("messageId");agentId=j.getString("agentId");agentName=j.getString("agentName");status=j.getString("status");error=j.getString("error");userId=j.isNull("userId")?"":j.optString("userId"); }
        String signature() { return messageId+":"+agentId+":"+status+":"+error; }
    }
    static final int MAX_BACKUP=32*1024*1024;
    JSONObject context(String room) throws Exception {return request("/api/conversations/context?conversationId="+encode(room),null);}
    JSONObject contextAction(String action,JSONObject body) throws Exception {return request("/api/conversations/context/"+action,body);}
    JSONObject clearPreview(String room) throws Exception {return request("/api/conversations/context/clear-preview?conversationId="+encode(room),null);}
    Conversation newThread(String agentId,String requestId,String name) throws Exception {
        return new Conversation(request("/api/conversations/direct/"+encode(agentId)+"/threads",new JSONObject().put("requestId",requestId).put("name",name)));
    }
    byte[] backup(String room) throws Exception {return requestBytes("/api/conversations/backups?conversationId="+encode(room),null,null,MAX_BACKUP);}
    Conversation restoreBackup(byte[] bytes,String requestId,String agentId) throws Exception {
        if(bytes.length==0||bytes.length>MAX_BACKUP)throw new IOException("备份不能超过 32 MB");
        String path="/api/conversations/backups?requestId="+encode(requestId)+(agentId.isEmpty()?"":"&agentId="+encode(agentId));
        return new Conversation(new JSONObject(new String(requestBytes(path,bytes,"application/zip",MAX_BACKUP),StandardCharsets.UTF_8)));
    }
    private static String encode(String value) throws Exception {return URLEncoder.encode(value,StandardCharsets.UTF_8.name());}
    List<Agent> agents() throws Exception { JSONArray rows=new JSONArray(requestText("/api/agents",null));List<Agent> result=new ArrayList<>();for(int i=0;i<rows.length();i++)result.add(new Agent(rows.getJSONObject(i)));return result; }
    List<Conversation> conversations() throws Exception { JSONArray rows=new JSONArray(requestText("/api/conversations",null));List<Conversation> result=new ArrayList<>();for(int i=0;i<rows.length();i++)result.add(new Conversation(rows.getJSONObject(i)));return result; }
    Conversation branch(String room,long message,String requestId,String name)throws Exception {
        if(message<=0||room==null||!room.matches("[A-Za-z0-9:-]{1,80}"))throw new IOException("分支消息标识无效");
        return new Conversation(request("/api/conversations/"+room+"/branches",new JSONObject().put("messageId",message).put("requestId",requestId).put("name",name)));
    }
    Conversation direct(String agentId) throws Exception { return new Conversation(request("/api/conversations/direct/"+agentId,new JSONObject())); }
    Conversation group(String name,List<String> agents,List<String> usernames)throws Exception{
        var body=new JSONObject().put("name",name).put("agentIds",new JSONArray(agents)).put("usernames",new JSONArray(usernames));
        return new Conversation(request("/api/conversations/groups",body));
    }
    List<User> members(String room,List<String> usernames)throws Exception{
        JSONObject body=usernames==null?null:new JSONObject().put("usernames",new JSONArray(usernames));
        JSONArray response=new JSONArray(requestText("/api/conversations/"+encode(room)+"/members",body));
        List<User> result=new ArrayList<>();
        for(int i=0;i<response.length();i++)result.add(new User(response.getJSONObject(i)));
        return result;
    }
    Conversation addAgents(String room,List<String> agentIds)throws Exception{
        return new Conversation(request("/api/conversations/"+encode(room)+"/agents",new JSONObject().put("agentIds",new JSONArray(agentIds))));
    }
    void retryJob(Job job) throws Exception { request("/api/device-messages/"+job.messageId+"/agents/"+job.agentId+"/retry",new JSONObject()); }
    void heartbeat(String deviceId, String name) throws Exception { request("/api/device-messages/presence",new JSONObject().put("deviceId",deviceId).put("name",name).put("platform","android")); }
    static final class Page {
        final List<Message> messages = new ArrayList<>();
        final boolean hasMore;
        final long historyRevision;
        final JSONArray contextOperations;
        final List<Job> jobs = new ArrayList<>();
        Page(JSONObject json) throws JSONException {
            JSONArray rows = json.getJSONArray("messages");
            for (int i = 0; i < rows.length(); i++) messages.add(new Message(rows.getJSONObject(i)));
            hasMore = json.getBoolean("hasMore");
            historyRevision=json.optLong("historyRevision",-1);contextOperations=json.optJSONArray("contextOperations")==null?new JSONArray():json.getJSONArray("contextOperations");
            JSONArray tasks=json.optJSONArray("jobs");if(tasks!=null)for(int i=0;i<tasks.length();i++)jobs.add(new Job(tasks.getJSONObject(i)));
        }
    }
    Page page(String conversation, Long after, Long before) throws Exception {
        String path = "/api/device-messages?limit=100&conversationId=" + URLEncoder.encode(conversation, StandardCharsets.UTF_8.name());
        if (after != null) path += "&after=" + after;
        if (before != null) path += "&before=" + before;
        return new Page(request(path, null));
    }
    static final class SearchHit {
        final Message message;final String conversationName;
        SearchHit(Message message,String name){this.message=message;conversationName=name;}
        SearchHit(JSONObject value)throws JSONException{message=new Message(value.getJSONObject("message"));conversationName=value.getString("conversationName");}
    }
    static final class SearchPage {
        final List<SearchHit> results=new ArrayList<>();final boolean hasMore;final Long nextBefore;
        SearchPage(JSONObject value)throws JSONException{
            JSONArray rows=value.getJSONArray("results");for(int i=0;i<rows.length();i++)results.add(new SearchHit(rows.getJSONObject(i)));
            hasMore=value.getBoolean("hasMore");nextBefore=value.isNull("nextBefore")?null:value.getLong("nextBefore");
        }
    }
    static final class SearchContext {
        final List<Message> messages=new ArrayList<>();final boolean hasOlder,hasNewer;final long historyRevision;
        SearchContext(JSONObject value)throws JSONException{
            JSONArray rows=value.getJSONArray("messages");for(int i=0;i<rows.length();i++)messages.add(new Message(rows.getJSONObject(i)));
            hasOlder=value.getBoolean("hasOlder");hasNewer=value.getBoolean("hasNewer");historyRevision=value.getLong("historyRevision");
        }
    }
    SearchPage search(String query,String room,Long before)throws Exception{
        String path="/api/device-messages/search?q="+encode(query);
        if(room!=null)path+="&conversationId="+encode(room);if(before!=null)path+="&before="+before;
        return new SearchPage(request(path,null));
    }
    SearchContext searchContext(String room,long message,String direction)throws Exception{
        return new SearchContext(request("/api/device-messages/context?conversationId="+encode(room)+"&messageId="+message+"&direction="+encode(direction),null));
    }
    Message send(JSONObject body) throws Exception {
        if(body.has("quoteMessageId")&&!request("/api/device-messages/features",null).optBoolean("quotes"))throw new IOException("服务端尚未支持引用回复，请先升级服务端。");
        var payload=new JSONObject(body.toString());payload.remove("quote");payload.remove("documents");return new Message(request("/api/device-messages",payload));
    }
    JSONObject notificationStatus()throws Exception{return request("/api/device-messages/notifications/status",null);}
    JSONObject notifications(String device,Long after,boolean preview)throws Exception{return request("/api/device-messages/notifications?deviceId="+encode(device)+"&preview="+preview+(after==null?"":"&after="+after),null);}
    void registerNotifications(JSONObject registration)throws Exception{request("/api/device-messages/notifications/devices",registration);}
    void removeNotifications(String device)throws Exception{request("/api/device-messages/notifications/devices/"+encode(device)+"/remove",new JSONObject());}
    void uploadDocument(ChatDocument doc,String room,byte[] data)throws Exception{
        if(data.length>ChatDocument.MAX_BYTES)throw new IOException("文件超过 10 MB。");
        requestBytes("/api/device-messages/documents?id="+encode(doc.id)+"&conversationId="+encode(room)+"&name="+encode(doc.name),data,"application/octet-stream");
    }
    byte[] document(String id,Long favorite)throws Exception{
        if(!id.matches("[a-fA-F0-9-]{36}"))throw new IOException("文档标识无效。");
        return requestBytes((favorite==null?"/api/device-messages/documents/":"/api/device-messages/favorites/"+favorite+"/documents/")+id,null,"application/octet-stream",ChatDocument.MAX_BYTES);
    }
    void uploadImage(String id,String room,byte[] data) throws Exception {
        if(!id.matches("[a-fA-F0-9-]{36}")||data.length>5*1024*1024)throw new IOException("图片无效或过大");
        requestBytes("/api/device-messages/images?id="+id+"&conversationId="+URLEncoder.encode(room,StandardCharsets.UTF_8.name()),data,"image/jpeg");
    }
    byte[] image(String id) throws Exception {
        if(!id.matches("[a-fA-F0-9-]{36}"))throw new IOException("图片标识无效");
        byte[] data=requestBytes("/api/device-messages/images/"+id,null);
        if(data.length>1024*1024)throw new IOException("图片过大");return data;
    }

    private JSONObject request(String path, JSONObject body) throws Exception { return new JSONObject(requestText(path,body)); }
    byte[] avatar(String id) throws Exception {
        if (!id.matches("[a-z0-9-]{1,80}")) throw new IOException("头像标识无效");
        byte[] data = requestBytes("/api/agent-avatars/"+id,null);
        if(data.length>2*1024*1024)throw new IOException("头像过大");return data;
    }
    private String requestText(String path, JSONObject body) throws Exception { return new String(requestBytes(path,body),StandardCharsets.UTF_8); }
    private byte[] requestBytes(String path, JSONObject body) throws Exception {
        return requestBytes(path,body==null?null:body.toString().getBytes(StandardCharsets.UTF_8),"application/json; charset=utf-8");
    }
    private byte[] requestBytes(String path, byte[] bytes, String contentType) throws Exception {
        return requestBytes(path,bytes,contentType,5_000_000);
    }
    private byte[] requestBytes(String path, byte[] bytes, String contentType,int limit) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(base + path).openConnection();
        try {
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(12000); connection.setReadTimeout(path.endsWith("/branches")?90000:path.startsWith("/api/conversations/backups")?60000:15000);
            connection.setUseCaches(false);
            connection.setRequestProperty("Authorization", "Bearer " + token);
            connection.setRequestProperty("Accept", "application/json");
            if (bytes != null) {
                connection.setRequestMethod("POST"); connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", contentType);
                connection.setFixedLengthStreamingMode(bytes.length);
                try (OutputStream stream = connection.getOutputStream()) { stream.write(bytes); }
            }
            int code = connection.getResponseCode();
            if(code==401&&token.startsWith("chat_"))throw new SessionExpired();
            if (code == 401) throw new IOException("访问令牌未通过认证，请检查令牌后重试。");
            if (code == 403) throw new IOException("服务器拒绝访问（HTTP 403）。请检查服务端接口权限或 HTTPS 代理配置。");
            if (code == 502 || code == 503 || code == 504) throw new IOException("服务暂时不可用（HTTP " + code + "），请检查服务端运行状态。");

            if (code == 413) throw new IOException("备份或图片超过服务允许的大小，请检查文件大小及服务端代理配置。");
            if (code < 200 || code >= 300) {
                String reason = "请求失败（HTTP " + code + "），请稍后重试。";
                if(code==404)reason=path.startsWith("/api/device-messages/search")?"服务端尚未支持聊天记录搜索，请先升级服务端。":path.equals("/api/agents/usage")?"服务端尚未支持 Token 用量，请先升级服务端。":
                    path.startsWith("/api/conversations/")?"服务端尚未支持此聊天功能，请先升级服务端。":"服务端尚未安装消息接口，请先升级服务端。";
                InputStream failure = connection.getErrorStream();
                if (failure != null) try (InputStream stream = failure; ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                    byte[] buffer = new byte[2048]; int n;
                    while ((n = stream.read(buffer)) != -1 && out.size() < 65536) out.write(buffer,0,n);
                    JSONObject error = new JSONObject(out.toString(StandardCharsets.UTF_8.name()));
                    reason = error.optString("message",error.optString("detail",reason));
                } catch (Exception ignored) { }
                throw new IOException(reason);
            }
            try (InputStream in = connection.getInputStream(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8192]; int n;
                while ((n = in.read(buffer)) != -1) {
                    if (out.size() + n > limit) throw new IOException("服务器响应过大。");
                    out.write(buffer, 0, n);
                }
                return out.toByteArray();
            }
        } catch (javax.net.ssl.SSLException e) {
            throw new IOException("HTTPS 证书验证失败，请检查服务地址及服务器证书。");
        } catch (SocketTimeoutException | UnknownHostException | ConnectException e) {
            throw new IOException("无法连接服务器，请检查网络与服务地址。");
        } finally { connection.disconnect(); }
    }
}
