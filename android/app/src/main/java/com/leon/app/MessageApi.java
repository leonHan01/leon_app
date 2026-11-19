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

    static final class Message {
        final long id, createdAt;
        final String clientMessageId, deviceId, sender, platform, text, conversationId, role, agentId;
        final List<String> imageIds = new ArrayList<>();
        Message(JSONObject json) throws JSONException {
            id = json.getLong("id"); createdAt = json.getLong("createdAt");
            clientMessageId = json.getString("clientMessageId"); deviceId = json.getString("deviceId");
            sender = json.getString("sender"); platform = json.getString("platform"); text = json.getString("text");
            conversationId = json.optString("conversationId", "shared"); role = json.optString("role", "user"); agentId = json.optString("agentId", "");
            JSONArray images=json.optJSONArray("images");if(images!=null)for(int i=0;i<images.length();i++)imageIds.add(images.getJSONObject(i).getString("id"));
        }
    }
    static final class Agent {
        final String id, name, handle, provider, avatarId; final boolean enabled;
        Agent(JSONObject j) throws JSONException { id=j.getString("id");name=j.getString("name");handle=j.getString("handle");provider=j.getString("provider");enabled=j.getBoolean("enabled");avatarId=j.optString("avatarId","alfred"); }
    }
    static final class Conversation {
        final String id,name,kind,agentId; final List<String> agentIds=new ArrayList<>();
        Conversation(JSONObject j) throws JSONException { id=j.getString("id");name=j.getString("name");kind=j.getString("kind");agentId=j.optString("agentId","");JSONArray ids=j.getJSONArray("agentIds");for(int i=0;i<ids.length();i++)agentIds.add(ids.getString(i)); }
    }
    static final class Job {
        final long messageId; final String agentId,agentName,status,error;
        Job(JSONObject j) throws JSONException { messageId=j.getLong("messageId");agentId=j.getString("agentId");agentName=j.getString("agentName");status=j.getString("status");error=j.getString("error"); }
        String signature() { return messageId+":"+agentId+":"+status+":"+error; }
    }
    List<Agent> agents() throws Exception { JSONArray rows=new JSONArray(requestText("/api/agents",null));List<Agent> result=new ArrayList<>();for(int i=0;i<rows.length();i++)result.add(new Agent(rows.getJSONObject(i)));return result; }
    List<Conversation> conversations() throws Exception { JSONArray rows=new JSONArray(requestText("/api/conversations",null));List<Conversation> result=new ArrayList<>();for(int i=0;i<rows.length();i++)result.add(new Conversation(rows.getJSONObject(i)));return result; }
    Conversation direct(String agentId) throws Exception { return new Conversation(request("/api/conversations/direct/"+agentId,new JSONObject())); }
    Conversation group(String name,List<String> ids) throws Exception { return new Conversation(request("/api/conversations/groups",new JSONObject().put("name",name).put("agentIds",new JSONArray(ids)))); }
    void retryJob(Job job) throws Exception { request("/api/device-messages/"+job.messageId+"/agents/"+job.agentId+"/retry",new JSONObject()); }
    void heartbeat(String deviceId, String name) throws Exception { request("/api/device-messages/presence",new JSONObject().put("deviceId",deviceId).put("name",name).put("platform","android")); }
    static final class Page {
        final List<Message> messages = new ArrayList<>();
        final boolean hasMore;
        final List<Job> jobs = new ArrayList<>();
        Page(JSONObject json) throws JSONException {
            JSONArray rows = json.getJSONArray("messages");
            for (int i = 0; i < rows.length(); i++) messages.add(new Message(rows.getJSONObject(i)));
            hasMore = json.getBoolean("hasMore");
            JSONArray tasks=json.optJSONArray("jobs");if(tasks!=null)for(int i=0;i<tasks.length();i++)jobs.add(new Job(tasks.getJSONObject(i)));
        }
    }
    Page page(String conversation, Long after, Long before) throws Exception {
        String path = "/api/device-messages?limit=100&conversationId=" + URLEncoder.encode(conversation, StandardCharsets.UTF_8.name());
        if (after != null) path += "&after=" + after;
        if (before != null) path += "&before=" + before;
        return new Page(request(path, null));
    }
    Message send(JSONObject body) throws Exception { return new Message(request("/api/device-messages", body)); }
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
        HttpURLConnection connection = (HttpURLConnection) new URL(base + path).openConnection();
        try {
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(12000); connection.setReadTimeout(15000);
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
            if (code == 401) throw new IOException("访问令牌未通过认证，请检查令牌后重试。");
            if (code == 403) throw new IOException("服务器拒绝访问（HTTP 403）。请检查服务端接口权限或 HTTPS 代理配置。");
            if (code == 502 || code == 503 || code == 504) throw new IOException("服务暂时不可用（HTTP " + code + "），请检查服务端运行状态。");
            if (code == 404) throw new IOException("服务端尚未安装消息接口，请先升级服务端。");
            if (code < 200 || code >= 300) {
                String reason = "请求失败（HTTP " + code + "），请稍后重试。";
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
                    if (out.size() + n > 5_000_000) throw new IOException("服务器响应过大。");
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
