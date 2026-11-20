package com.leon.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.widget.ImageView;
import android.widget.FrameLayout;
import android.view.Gravity;
import android.widget.Toast;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class ChatImageActions {
    static final class Document {
        final byte[] data;final int connection;
        Document(byte[] data,int connection){this.data=data;this.connection=connection;}
    }
    private static final int SAVE_DOCUMENT=45;
    private final Activity activity;
    private final ChatSession session;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final Set<String> saving=new HashSet<>();
    private String documentKey;
    ChatImageActions(Activity activity,ChatSession session){this.activity=activity;this.session=session;}
    void bind(ImageView image,String id){bind(image,id,null);}
    void bind(ImageView image,String id,Runnable messageActions){
        image.setContentDescription("聊天图片，点击查看大图，长按保存图片");
        image.setOnLongClickListener(view->{
            new AlertDialog.Builder(activity).setItems(messageActions==null?new String[]{"保存图片"}:new String[]{"保存图片","消息操作"},(dialog,which)->{if(which==0)save(id);else messageActions.run();}).show();return true;
        });
        image.setOnClickListener(view->preview(id,messageActions));
    }
    private void preview(String id,Runnable messageActions){
        ImageView large=new ImageView(activity);large.setScaleType(ImageView.ScaleType.FIT_CENTER);large.setAdjustViewBounds(true);
        session.bindImage(large,id,true);bind(large,id,messageActions);large.setOnClickListener(null);
        var ui=new ChatUi(activity);FrameLayout content=new FrameLayout(activity);content.setMinimumHeight(ui.dp(180));
        content.addView(large,new FrameLayout.LayoutParams(-1,-2));
        var download=ui.icon(R.drawable.ic_download,"下载并保存图片");download.setId(R.id.download_chat_image);
        download.setTooltipText("下载并保存图片");download.setBackground(ui.ripple(0xF2FFFFFF,24));download.setElevation(ui.dp(4));
        download.setPadding(ui.dp(12),ui.dp(12),ui.dp(12),ui.dp(12));download.setOnClickListener(view->save(id));
        var position=new FrameLayout.LayoutParams(ui.dp(48),ui.dp(48),Gravity.BOTTOM|Gravity.END);
        position.setMargins(ui.dp(16),ui.dp(16),ui.dp(16),ui.dp(16));content.addView(download,position);
        AlertDialog preview=new AlertDialog.Builder(activity).setTitle("图片预览").setView(content)
                .setNegativeButton("关闭",null).create();
        preview.setOnShowListener(dialog->session.refreshImages());
        preview.show();
    }
    private boolean active(int connection){return !activity.isFinishing()&&!activity.isDestroyed()&&connection==session.connectionStamp();}
    private void message(String text){if(!activity.isFinishing()&&!activity.isDestroyed())Toast.makeText(activity,text,Toast.LENGTH_LONG).show();}
    void save(String id){
        int connection=session.connectionStamp();String key=connection+":"+id;
        if(!saving.add(key)){message("正在保存图片…");return;}
        var source=session.imageSource(id);var resolver=activity.getContentResolver();String name="Leon-"+UUID.randomUUID()+".jpg";
        message("正在保存图片…");
        worker.execute(()->{
            try {
                byte[] data=source.load();ChatImageSaver.validate(data);
                main.post(()->{
                    if(!active(connection)){saving.remove(key);return;}
                    if(Build.VERSION.SDK_INT>=29){
                        worker.execute(()->{
                            String notice;
                            try{ChatImageSaver.gallery(resolver,data,name);notice="已保存到系统相册（Pictures/Leon）";}
                            catch(Exception failure){notice="保存失败，请检查可用空间或系统相册后重试";}
                            String result=notice;main.post(()->{saving.remove(key);if(active(connection))message(result);});
                        });
                    }else{
                        if(session.imageExport!=null){saving.remove(key);message("请先完成当前图片保存");return;}
                        session.imageExport=new Document(data,connection);documentKey=key;
                        try{
                            Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/jpeg").putExtra(Intent.EXTRA_TITLE,name);
                            activity.startActivityForResult(intent,SAVE_DOCUMENT);
                        }catch(Exception failure){clearDocument();message("无法打开保存位置选择器，请稍后重试");}
                    }
                });
            }catch(Exception failure){main.post(()->{saving.remove(key);if(active(connection))message("图片加载失败，请重新加载图片后重试");});}
        });
    }
    boolean result(int request,int result,Intent intent){
        if(request!=SAVE_DOCUMENT)return false;
        Document pending=session.imageExport;clearDocument();
        if(result!=Activity.RESULT_OK||intent==null||intent.getData()==null||pending==null)return true;
        byte[] data=pending.data;int connection=pending.connection;
        if(!active(connection)){message("连接已切换，请重新保存图片");return true;}
        var uri=intent.getData();var resolver=activity.getContentResolver();
        worker.execute(()->{
            String notice;
            try{ChatImageSaver.write(resolver,uri,data);notice="图片已保存";}
            catch(Exception failure){notice="图片保存失败，请检查保存位置和可用空间";}
            String text=notice;main.post(()->{if(active(connection))message(text);});
        });return true;
    }
    private void clearDocument(){if(documentKey!=null)saving.remove(documentKey);documentKey=null;session.imageExport=null;}
    void close(){if(!activity.isChangingConfigurations())clearDocument();worker.shutdown();}
}
