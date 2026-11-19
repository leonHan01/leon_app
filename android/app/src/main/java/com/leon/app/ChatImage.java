package com.leon.app;

import android.content.ContentResolver;
import android.graphics.*;
import androidx.exifinterface.media.ExifInterface;
import android.net.Uri;
import android.util.AtomicFile;
import java.io.*;
import java.util.UUID;

final class ChatImage {
    final String id;
    final byte[] data;
    ChatImage(String id, byte[] data) { this.id=id; this.data=data; }

    static ChatImage read(ContentResolver resolver, Uri uri) throws Exception {
        if (!"content".equals(uri.getScheme()) && !"file".equals(uri.getScheme())) throw new IOException("请选择本地图片");
        byte[] input;
        try (InputStream stream=resolver.openInputStream(uri)) {
            if(stream==null)throw new IOException("图片无法读取");
            input=readBounded(stream,20*1024*1024);
        }
        if(input.length>20*1024*1024)throw new IOException("图片文件过大，请选择小于 20 MB 的图片");
        var options=new BitmapFactory.Options();options.inJustDecodeBounds=true;
        BitmapFactory.decodeByteArray(input,0,input.length,options);
        int width=options.outWidth,height=options.outHeight;
        if(width<1||height<1||width>16000||height>16000||(long)width*height>48_000_000)throw new IOException("图片无法读取或尺寸过大");
        int sample=1;while(Math.max(width,height)/sample>1600)sample*=2;
        options.inJustDecodeBounds=false;options.inSampleSize=sample;options.inPreferredConfig=Bitmap.Config.ARGB_8888;
        Bitmap source=BitmapFactory.decodeByteArray(input,0,input.length,options);
        if(source==null)throw new IOException("图片格式不受支持");
        try {
            Matrix orientation=new Matrix();
            try {
                int exif=new ExifInterface(new ByteArrayInputStream(input)).getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL);
                switch(exif){
                    case ExifInterface.ORIENTATION_FLIP_HORIZONTAL:orientation.setScale(-1,1);break;
                    case ExifInterface.ORIENTATION_ROTATE_180:orientation.setRotate(180);break;
                    case ExifInterface.ORIENTATION_FLIP_VERTICAL:orientation.setScale(1,-1);break;
                    case ExifInterface.ORIENTATION_TRANSPOSE:orientation.setRotate(90);orientation.postScale(-1,1);break;
                    case ExifInterface.ORIENTATION_ROTATE_90:orientation.setRotate(90);break;
                    case ExifInterface.ORIENTATION_TRANSVERSE:orientation.setRotate(270);orientation.postScale(-1,1);break;
                    case ExifInterface.ORIENTATION_ROTATE_270:orientation.setRotate(270);break;
                    default:break;
                }
            }catch(IOException ignored){ }
            float scale=Math.min(1f,1600f/Math.max(source.getWidth(),source.getHeight()));orientation.postScale(scale,scale);
            Bitmap rotated=Bitmap.createBitmap(source,0,0,source.getWidth(),source.getHeight(),orientation,true);
            Bitmap normalized=Bitmap.createBitmap(rotated.getWidth(),rotated.getHeight(),Bitmap.Config.ARGB_8888);
            Canvas canvas=new Canvas(normalized);canvas.drawColor(Color.WHITE);canvas.drawBitmap(rotated,0,0,new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG));
            if(rotated!=source)rotated.recycle();
            try {
                for(int quality:new int[]{85,65,45}) {
                    var output=new ByteArrayOutputStream();normalized.compress(Bitmap.CompressFormat.JPEG,quality,output);
                    if(output.size()<=1024*1024)return new ChatImage(UUID.randomUUID().toString(),output.toByteArray());
                }
            }finally{normalized.recycle();}
            throw new IOException("图片压缩后仍过大，请缩小后发送");
        }finally{source.recycle();}
    }

    private static byte[] readBounded(InputStream stream,int limit) throws IOException {
        var output=new ByteArrayOutputStream();byte[] buffer=new byte[8192];int read;
        while((read=stream.read(buffer))!=-1){if(output.size()+read>limit)throw new IOException("图片文件过大");output.write(buffer,0,read);}
        return output.toByteArray();
    }
    static File file(File base,String scope,String id) throws IOException {
        if(scope==null||!id.matches("[a-fA-F0-9-]{36}"))throw new IOException("图片存储不可用");
        File directory=new File(new File(base,"chat-images"),scope);
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建图片目录");
        return new File(directory,id+".jpg");
    }
    void save(File base,String scope) throws IOException {
        AtomicFile file=new AtomicFile(file(base,scope,id));FileOutputStream output=file.startWrite();
        try{output.write(data);file.finishWrite(output);}catch(IOException failure){file.failWrite(output);throw failure;}
    }
    static byte[] local(File base,String scope,String id) throws IOException {
        File file=file(base,scope,id);if(!file.exists())return null;
        try(InputStream stream=new FileInputStream(file)){return readBounded(stream,1024*1024);}
    }
    static void remove(File base,String scope,String id) {try{new AtomicFile(file(base,scope,id)).delete();}catch(IOException ignored){}}
}
