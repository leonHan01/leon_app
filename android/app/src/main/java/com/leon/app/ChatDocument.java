package com.leon.app;

import android.content.ContentResolver;
import android.net.Uri;
import android.provider.OpenableColumns;
import org.json.*;
import java.io.*;
import java.util.*;

final class ChatDocument {
    static final int MAX_BYTES=10*1024*1024;
    static final Set<String> EXT=Set.of("pdf","txt","doc","docx","xls","xlsx","md","markdown","csv");
    final String id,name,mimeType;final int byteCount,characterCount;final boolean truncated;final byte[] data;
    ChatDocument(JSONObject value)throws JSONException{id=value.getString("id");name=value.getString("name");mimeType=value.optString("mimeType","application/octet-stream");byteCount=value.getInt("byteCount");characterCount=value.optInt("characterCount");truncated=value.optBoolean("truncated");data=null;}
    ChatDocument(String name,byte[] data){id=UUID.randomUUID().toString();this.name=name;this.data=data;byteCount=data.length;characterCount=0;truncated=false;mimeType="application/octet-stream";}
    JSONObject json()throws JSONException{return new JSONObject().put("id",id).put("name",name).put("mimeType",mimeType).put("byteCount",byteCount).put("characterCount",characterCount).put("truncated",truncated);}
    String detail(){return (byteCount<1024?byteCount+" B":String.format(Locale.ROOT,"%.1f KB",byteCount/1024.0))+(characterCount>0?" · 已提取 "+characterCount+" 字符":"")+(truncated?" · 长文已截取":"");}
    static ChatDocument read(ContentResolver resolver,Uri uri)throws Exception{
        String name="";try(var cursor=resolver.query(uri,new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE},null,null,null)){
            if(cursor!=null&&cursor.moveToFirst()){name=cursor.getString(0);if(!cursor.isNull(1)&&cursor.getLong(1)>MAX_BYTES)throw new IOException("每个文档不能超过 10 MB。");}
        }
        if(name==null||name.isBlank()||name.length()>180||name.contains("/")||name.contains("\\")||name.chars().anyMatch(Character::isISOControl))throw new IOException("文件名无效。");
        String ext=name.substring(name.lastIndexOf('.')+1).toLowerCase(Locale.ROOT);if(!EXT.contains(ext))throw new IOException("支持 PDF、TXT、Word、Excel、Markdown 和 CSV 文件。");
        try(var input=resolver.openInputStream(uri)){if(input==null)throw new IOException("无法读取所选文件。");byte[] bytes=bounded(input);if(bytes.length==0)throw new IOException("不能发送空文件。");return new ChatDocument(name,bytes);}
    }
    static byte[] bounded(InputStream input)throws IOException{
        var output=new ByteArrayOutputStream();byte[] buffer=new byte[65536];int n;
        while((n=input.read(buffer))!=-1){if(output.size()+n>MAX_BYTES)throw new IOException("文件超过 10 MB。");output.write(buffer,0,n);}return output.toByteArray();
    }
    static File file(File root,String scope,String id)throws IOException{
        if(!id.matches("[a-fA-F0-9-]{36}")||scope==null||!scope.matches("outbox\\.[a-f0-9]{64}"))throw new IOException("文档存储标识无效。");
        File folder=new File(root,"chat-documents/"+scope);if(!folder.exists()&&!folder.mkdirs())throw new IOException("无法保存待发文档。");return new File(folder,id);
    }
    void save(File root,String scope)throws IOException{File destination=file(root,scope,id),temporary=new File(destination+".tmp");try(var output=new FileOutputStream(temporary)){output.write(data);output.getFD().sync();}if(!temporary.renameTo(destination)){temporary.delete();throw new IOException("无法保存待发文档。");}}
    static byte[] local(File root,String scope,String id)throws IOException{try(var input=new FileInputStream(file(root,scope,id))){return bounded(input);}}
    static void remove(File root,String scope,String id){try{file(root,scope,id).delete();}catch(IOException ignored){}}
    static List<ChatDocument> parse(JSONArray array)throws JSONException{var items=new ArrayList<ChatDocument>();if(array!=null)for(int i=0;i<array.length();i++)items.add(new ChatDocument(array.getJSONObject(i)));return items;}
}
