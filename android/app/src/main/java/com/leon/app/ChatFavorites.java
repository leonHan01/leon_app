package com.leon.app;

import android.app.*;
import android.graphics.Color;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.BiConsumer;

/** Private server-backed collection; thumbnails use the favorite-owned image endpoint. */
final class ChatFavorites {
    private final ChatDocuments documents;
    private final Activity activity;private final ChatSession session;private final ChatUi ui;
    private final BiConsumer<MessageApi.Message,String> source;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newFixedThreadPool(2);
    private Dialog dialog;private LinearLayout root,rows,bar;private EditText query;private ScrollView scroll;
    private ChatImageLoader images;private Future<?> request;private Runnable debounce;
    private int connection,generation;private boolean busy,more,wasDetail;private int listOffset;private Long before;private String error="";
    private final List<MessageApi.Favorite> items=new ArrayList<>();private MessageApi.Favorite selected,failedRemoval;
    ChatFavorites(Activity activity,ChatSession session,BiConsumer<MessageApi.Message,String> source){this.activity=activity;this.session=session;this.source=source;ui=new ChatUi(activity);documents=new ChatDocuments(activity,session);}
    void show(){
        dismiss();if(!session.configured())return;connection=session.connectionStamp();images=new ChatImageLoader();selected=null;items.clear();before=null;more=false;error="";
        dialog=new Dialog(activity,android.R.style.Theme_Material_Light_NoActionBar);root=column();root.setBackgroundColor(Color.WHITE);bar=row();bar.setGravity(Gravity.CENTER_VERTICAL);root.addView(bar);root.addView(ui.divider(0));
        query=new EditText(activity);query.setSingleLine();query.setHint("搜索收藏");query.setTextColor(Color.BLACK);query.setHintTextColor(Color.BLACK);query.setTextSize(15);query.setPadding(ui.dp(14),ui.dp(8),ui.dp(14),ui.dp(8));query.setBackground(ui.shape(ChatUi.BAR,8));root.addView(query,new LinearLayout.LayoutParams(-1,ui.dp(46)));
        scroll=new ScrollView(activity);rows=column();rows.setPadding(ui.dp(14),ui.dp(10),ui.dp(14),ui.dp(14));scroll.addView(rows);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));scroll.setOnScrollChangeListener((v,x,y,ox,oy)->{if(images!=null)images.refresh();});
        Dialog owned=dialog;LinearLayout ownedRoot=root;ChatImageLoader ownedImages=images;
        dialog.setContentView(root);dialog.setOnDismissListener(d->{ownedImages.close();RichMarkdownView.releaseTree(ownedRoot);if(dialog==owned){stop();items.clear();dialog=null;}});
        dialog.setOnKeyListener((d,key,event)->{if(key==KeyEvent.KEYCODE_BACK&&event.getAction()==KeyEvent.ACTION_UP&&selected!=null){selected=null;query.setVisibility(View.VISIBLE);render();return true;}return false;});
        dialog.show();if(dialog.getWindow()!=null){dialog.getWindow().setLayout(-1,-1);dialog.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE|WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);}
        query.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int a,int c,int f){}public void afterTextChanged(Editable e){}public void onTextChanged(CharSequence s,int a,int b,int c){reload(true);}});
        reload(false);
    }
    boolean result(int request,int result,android.content.Intent data){return documents.result(request,result,data);}
    void changed(){if(dialog!=null&&connection!=session.connectionStamp())dismiss();}
    private boolean valid(int stamp){return dialog!=null&&dialog.isShowing()&&connection==session.connectionStamp()&&stamp==generation;}
    private void stop(){generation++;if(debounce!=null)main.removeCallbacks(debounce);if(request!=null)request.cancel(true);busy=false;}
    void dismiss(){stop();if(dialog!=null){var old=dialog;dialog=null;old.dismiss();}items.clear();selected=null;}
    void close(){dismiss();worker.shutdownNow();documents.close();}
    private void reload(boolean delayed){
        stop();before=null;more=false;items.clear();error="";failedRemoval=null;String q=query.getText().toString().trim();
        if(q.length()>100){error="搜索词最多 100 字符";render();return;}
        busy=true;int stamp=generation;render();debounce=()->{if(valid(stamp))load(false);};main.postDelayed(debounce,delayed?350:0);
    }
    private void load(boolean append){
        var api=session.searchClient();if(api==null)return;busy=true;error="";int stamp=generation;String q=query.getText().toString().trim();Long cursor=append?before:null;render();
        request=worker.submit(()->{
            try{var page=api.favorites(q,cursor);main.post(()->{if(!valid(stamp))return;if(!append)items.clear();Set<Long> known=new HashSet<>();for(var item:items)known.add(item.id);for(var item:page.results)if(known.add(item.id))items.add(item);before=page.nextBefore;more=page.hasMore&&before!=null;busy=false;render();});}
            catch(Exception failure){main.post(()->{if(valid(stamp)){session.searchFailure(failure);if(!valid(stamp))return;busy=false;error=failure.getMessage()==null?"无法读取收藏，请重试。":failure.getMessage();render();}});}
        });
    }
    private void render(){
        int previous=selected!=null?0:wasDetail?listOffset:scroll.getScrollY();wasDetail=selected!=null;bar.removeAllViews();RichMarkdownView.releaseTree(rows);rows.removeAllViews();
        Button back=button(selected==null?"关闭":"‹ 收藏");back.setOnClickListener(v->{if(selected==null)dismiss();else{selected=null;query.setVisibility(View.VISIBLE);render();}});bar.addView(back);
        TextView title=ui.text(selected==null?"我的收藏":"收藏详情",17,ChatUi.INK);title.setGravity(Gravity.CENTER);bar.addView(title,new LinearLayout.LayoutParams(0,ui.dp(52),1));
        Button action=button(selected==null?"刷新":"取消收藏");action.setEnabled(!busy);action.setOnClickListener(v->{if(selected==null)reload(false);else confirmRemove(selected);});bar.addView(action);
        if(selected!=null){detail(selected);}else{
            for(var item:items){
                LinearLayout card=column();card.setPadding(ui.dp(14),ui.dp(14),ui.dp(14),ui.dp(14));card.setBackground(ui.ripple(ChatUi.BAR,9));card.setTag("favorite:"+item.id);card.setFocusable(true);
                TextView sender=ui.text(item.message.sender+" · "+date(item.message.createdAt),12,Color.BLACK);card.addView(sender);
                if(!item.message.text.isEmpty()){TextView text=ui.text(item.message.text,15,ChatUi.INK);text.setMaxLines(3);text.setPadding(0,ui.dp(10),0,ui.dp(8));card.addView(text);}
                for(var doc:item.message.documents)card.addView(ui.text("[文件] "+doc.name,14,Color.BLACK));
                if(!item.message.imageIds.isEmpty())addImage(card,item,item.message.imageIds.get(0),110);
                TextView origin=ui.text("来自："+item.conversationName,12,Color.BLACK);origin.setPadding(0,ui.dp(8),0,0);card.addView(origin);
                card.setOnClickListener(v->{listOffset=scroll.getScrollY();stop();error="";selected=item;query.setVisibility(View.GONE);render();});card.setOnLongClickListener(v->{confirmRemove(item);return true;});
                LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(-1,-2);params.bottomMargin=ui.dp(12);rows.addView(card,params);
            }
            if(items.isEmpty()&&!busy&&error.isEmpty())notice(query.length()==0?"暂无收藏\n长按聊天消息，选择“收藏”":"未找到相关收藏");
            if(more&&!busy){Button next=button("加载更多收藏");next.setOnClickListener(v->load(true));rows.addView(next);}
        }
        if(busy)notice("正在读取收藏…");if(!error.isEmpty()){notice(error);Button retry=button("重试");retry.setOnClickListener(v->{if(failedRemoval!=null)remove(failedRemoval);else if(items.isEmpty()||!more)reload(false);else load(true);});rows.addView(retry);}
        scroll.post(()->{scroll.scrollTo(0,previous);if(images!=null)images.refresh();});
    }
    private void detail(MessageApi.Favorite item){
        notice(item.message.sender+" · "+date(item.message.createdAt));
        if(item.message.quote!=null)notice("引用 "+item.message.quote.sender+"："+item.message.quote.preview());
        if(!item.message.text.isEmpty()){
            if(RichMarkdownView.isRequired(item.message.text))rows.addView(new RichMarkdownView(activity,item.message.text,false),new LinearLayout.LayoutParams(-1,-2));
            else{TextView body=ui.text("",15,ChatUi.INK);new MessageMarkdown(activity).setText(body,item.message.text,false);body.setTextIsSelectable(true);rows.addView(body);}
        }
        for(var doc:item.message.documents)rows.addView(documents.card(doc,item.id,null,null));
        for(String image:item.message.imageIds)addImage(rows,item,image,220);
        notice("来自："+item.conversationName);Button locate=button("查看原消息");locate.setOnClickListener(v->source.accept(item.message,item.conversationName));rows.addView(locate);
    }
    private void addImage(LinearLayout parent,MessageApi.Favorite item,String id,int size){
        ImageView image=new ImageView(activity);image.setScaleType(ImageView.ScaleType.FIT_CENTER);parent.addView(image,new LinearLayout.LayoutParams(ui.dp(size),ui.dp(size*.75f)));
        MessageApi api=session.searchClient();if(api!=null&&images!=null)images.bind(image,connection+":"+item.id+":"+id,()->api.favoriteImage(item.id,id),false);
    }
    private void confirmRemove(MessageApi.Favorite item){new AlertDialog.Builder(activity).setTitle("取消这条收藏？").setMessage("聊天中的原消息不受影响。").setNegativeButton("保留",null).setPositiveButton("取消收藏",(d,w)->remove(item)).show();}
    private void remove(MessageApi.Favorite item){
        if(busy)return;var api=session.searchClient();if(api==null)return;busy=true;int stamp=generation;error="";failedRemoval=null;render();
        request=worker.submit(()->{try{api.removeFavorite(item.id);main.post(()->{if(!valid(stamp))return;items.removeIf(i->i.id==item.id);selected=null;query.setVisibility(View.VISIBLE);busy=false;render();});}catch(Exception e){main.post(()->{if(valid(stamp)){busy=false;failedRemoval=item;error=e.getMessage()==null?"操作未完成，请重试。":e.getMessage();render();}});}});
    }
    private void notice(String text){TextView view=ui.text(text,13,Color.BLACK);view.setPadding(ui.dp(8),ui.dp(14),ui.dp(8),ui.dp(14));rows.addView(view);}
    private static String date(long timestamp){return java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.SHORT,java.text.DateFormat.SHORT).format(new Date(timestamp));}
    private Button button(String label){Button view=ui.button(label);view.setTextColor(Color.BLACK);view.setTypeface(android.graphics.Typeface.create("sans-serif",android.graphics.Typeface.NORMAL));return view;}
    private LinearLayout column(){LinearLayout view=new LinearLayout(activity);view.setOrientation(LinearLayout.VERTICAL);return view;}
    private LinearLayout row(){LinearLayout view=new LinearLayout(activity);view.setOrientation(LinearLayout.HORIZONTAL);return view;}
}
