package com.leon.app;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;
import java.io.IOException;
import java.io.OutputStream;

/** Save the attachment bytes, never the downsampled ImageView bitmap. */
final class ChatImageSaver {
    static void validate(byte[] data) throws IOException {
        if(data==null||data.length==0||data.length>1024*1024)throw new IOException("图片数据为空或过大，请重新加载后重试");
        var bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;
        BitmapFactory.decodeByteArray(data,0,data.length,bounds);
        if(bounds.outWidth<1||bounds.outHeight<1||bounds.outWidth>1600||bounds.outHeight>1600||!"image/jpeg".equals(bounds.outMimeType))
            throw new IOException("图片数据无效，请重新加载后重试");
    }
    @android.annotation.TargetApi(29)
    static Uri gallery(ContentResolver resolver,byte[] data,String name) throws IOException {
        validate(data);
        var values=new ContentValues();values.put(MediaStore.Images.Media.DISPLAY_NAME,name);
        values.put(MediaStore.Images.Media.MIME_TYPE,"image/jpeg");
        values.put(MediaStore.Images.Media.RELATIVE_PATH,Environment.DIRECTORY_PICTURES+"/Leon");
        values.put(MediaStore.Images.Media.IS_PENDING,1);
        Uri uri=resolver.insert(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),values);
        if(uri==null)throw new IOException("无法创建相册图片，请检查可用空间后重试");
        boolean published=false;
        try {
            write(resolver,uri,data);
            var complete=new ContentValues();complete.put(MediaStore.Images.Media.IS_PENDING,0);
            if(resolver.update(uri,complete,null,null)!=1)throw new IOException("图片未能保存到相册，请重试");
            published=true;return uri;
        } finally {
            if(!published)try{resolver.delete(uri,null,null);}catch(Exception ignored){}
        }
    }
    static void write(ContentResolver resolver,Uri uri,byte[] data) throws IOException {
        try(OutputStream output=resolver.openOutputStream(uri,"w")){
            if(output==null)throw new IOException("无法写入图片，请换一个保存位置");
            output.write(data);output.flush();
        }
    }
}
