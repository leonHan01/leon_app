package com.leon.app;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.util.LruCache;
import android.widget.ImageView;
import java.lang.ref.WeakReference;
import java.util.*;
import java.util.concurrent.*;

/** Decode only visible attachments; offscreen views do not retain decoded bitmaps. */
final class ChatImageLoader {
    interface Source { byte[] load() throws Exception; }
    private static final class Binding {
        final WeakReference<ImageView> view;
        final String key;
        final Source source;
        final int pixels;
        boolean displayed, loading, failed;
        Binding(ImageView view,String key,Source source,int pixels){this.view=new WeakReference<>(view);this.key=key;this.source=source;this.pixels=pixels;}
    }
    private final ExecutorService workers=Executors.newFixedThreadPool(2);
    private final Handler main=new Handler(Looper.getMainLooper());
    private final LruCache<String,Bitmap> cache=new LruCache<String,Bitmap>(24*1024){
        @Override protected int sizeOf(String key,Bitmap bitmap){return Math.max(1,bitmap.getAllocationByteCount()/1024);}
    };
    private final List<Binding> bindings=new ArrayList<>();
    private int generation;
    private boolean scheduled;
    void bind(ImageView view,String key,Source source,boolean large){
        String cacheKey=key+(large?":large":":thumb");
        view.setTag(cacheKey);view.setImageResource(android.R.drawable.ic_menu_gallery);view.setContentDescription("聊天图片，点击查看大图");
        bindings.add(new Binding(view,cacheKey,source,large?1600:512));
        view.post(this::refresh);
    }
    void refresh(){
        if(scheduled||workers.isShutdown())return;scheduled=true;
        main.postDelayed(()->{scheduled=false;refreshVisible();},80);
    }
    private static boolean visible(ImageView view){return view.isShown()&&view.getGlobalVisibleRect(new Rect());}
    private void refreshVisible(){
        for(Iterator<Binding> iterator=bindings.iterator();iterator.hasNext();){
            Binding binding=iterator.next();ImageView view=binding.view.get();
            if(view==null||!binding.key.equals(view.getTag())||!view.isAttachedToWindow()){iterator.remove();continue;}
            if(!visible(view)){
                if(binding.displayed){view.setImageResource(android.R.drawable.ic_menu_gallery);binding.displayed=false;}
                continue;
            }
            if(binding.displayed||binding.loading||binding.failed)continue;
            Bitmap cached=cache.get(binding.key);
            if(cached!=null){view.setImageBitmap(cached);binding.displayed=true;continue;}
            binding.loading=true;int epoch=generation;
            workers.execute(()->{
                Bitmap bitmap=null;
                try{
                    byte[] data=binding.source.load();var options=new BitmapFactory.Options();options.inJustDecodeBounds=true;
                    BitmapFactory.decodeByteArray(data,0,data.length,options);int sample=1;
                    if(options.outWidth<1||options.outHeight<1||options.outWidth>1600||options.outHeight>1600)throw new java.io.IOException("图片尺寸无效");
                    while(Math.max(options.outWidth,options.outHeight)/sample>binding.pixels)sample*=2;
                    options.inJustDecodeBounds=false;options.inSampleSize=sample;
                    bitmap=BitmapFactory.decodeByteArray(data,0,data.length,options);
                }catch(Exception ignored){}
                Bitmap result=bitmap;
                main.post(()->{
                    if(epoch!=generation)return;binding.loading=false;
                    if(result!=null)cache.put(binding.key,result);
                    ImageView target=binding.view.get();
                    if(target==null||!binding.key.equals(target.getTag())||!visible(target))return;
                    if(result!=null){target.setImageBitmap(result);binding.displayed=true;}
                    else{binding.failed=true;target.setImageResource(android.R.drawable.ic_menu_report_image);target.setContentDescription("图片加载失败，点击重试");}
                });
            });
        }
    }
    void clear(){generation++;cache.evictAll();bindings.clear();}
    void close(){clear();workers.shutdownNow();}
}
