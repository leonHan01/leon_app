package com.leon.app;

import android.app.*;
import android.content.*;
import android.graphics.Color;
import android.os.*;
import android.text.*;
import android.text.style.ForegroundColorSpan;
import android.view.*;
import android.view.inputmethod.*;
import android.widget.*;
import java.text.DateFormat;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;
import java.util.regex.Pattern;

/** Search has independent cursors; reading a match never changes the live chat's outbox or cache. */
final class ChatSearch {
    private final Activity activity;
    private final ChatSession session;
    private final ChatUi ui;
    private final ChatImageActions imageActions;
    private final boolean ownsImageActions;
    private final Consumer<String> enter;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newFixedThreadPool(2);
    private Future<?> request;
    private Runnable debounce;
    private Dialog dialog;
    private LinearLayout root,entry,results,historyBar,historyRows;
    private EditText input;
    private ScrollView resultScroll,historyScroll;
    private String room,title,query="",lastDirection="around";
    private int connection,generation;
    private Long before,historyRevision;
    private boolean busy,searched,hasMore,hasOlder,hasNewer,followAnchor;
    private View focusedMessage;
    private String error="";
    private final List<MessageApi.SearchHit> hits=new ArrayList<>();
    private final List<MessageApi.Message> messages=new ArrayList<>();
    private MessageApi.SearchHit selected;
    ChatSearch(Activity activity,ChatSession session,Consumer<String> enter){
        this(activity,session,enter,null);
    }
    ChatSearch(Activity activity,ChatSession session,Consumer<String> enter,ChatImageActions imageActions){
        this.activity=activity;this.session=session;this.enter=enter;ui=new ChatUi(activity);
        ownsImageActions=imageActions==null;this.imageActions=ownsImageActions?new ChatImageActions(activity,session):imageActions;
    }
    void show(String room,String title){
        dismiss();if(!session.configured())return;
        this.room=room;this.title=title;connection=session.connectionStamp();query="";before=null;selected=null;
        hits.clear();messages.clear();busy=false;searched=false;hasMore=false;error="";
        dialog=new Dialog(activity,android.R.style.Theme_Material_Light_NoActionBar);
        root=column();root.setBackgroundColor(Color.WHITE);
        entry=column();entry.setPadding(ui.dp(12),ui.dp(10),ui.dp(12),ui.dp(10));
        TextView scope=ui.text(title,16,ChatUi.INK);scope.setPadding(ui.dp(4),0,0,ui.dp(12));entry.addView(scope);
        LinearLayout bar=row();bar.setGravity(Gravity.CENTER_VERTICAL);
        ImageView icon=new ImageView(activity);icon.setImageResource(R.drawable.ic_search);icon.setPadding(ui.dp(8),0,ui.dp(8),0);bar.addView(icon,new LinearLayout.LayoutParams(ui.dp(36),ui.dp(40)));
        input=new EditText(activity);input.setSingleLine();input.setHint("搜索聊天记录");input.setTextSize(16);input.setTextColor(ChatUi.INK);
        input.setImeOptions(EditorInfo.IME_ACTION_SEARCH);input.setId(R.id.chat_search_input);input.setBackground(ui.shape(ChatUi.BAR,8));
        bar.addView(input,new LinearLayout.LayoutParams(0,ui.dp(44),1));
        Button clear=ui.button("清除");clear.setContentDescription("清除搜索词");clear.setOnClickListener(v->input.setText(""));bar.addView(clear);
        Button cancel=ui.button("取消");cancel.setOnClickListener(v->dismiss());bar.addView(cancel);entry.addView(bar);root.addView(entry);
        historyBar=row();historyBar.setGravity(Gravity.CENTER_VERTICAL);historyBar.setPadding(ui.dp(6),0,ui.dp(6),0);historyBar.setVisibility(View.GONE);root.addView(historyBar);
        root.addView(ui.divider(0));
        resultScroll=new ScrollView(activity);results=column();results.setId(R.id.chat_search_results);resultScroll.addView(results);root.addView(resultScroll,new LinearLayout.LayoutParams(-1,0,1));
        historyScroll=new ScrollView(activity);historyRows=column();historyRows.setPadding(ui.dp(12),ui.dp(12),ui.dp(12),ui.dp(12));historyScroll.addView(historyRows);historyScroll.setVisibility(View.GONE);root.addView(historyScroll,new LinearLayout.LayoutParams(-1,0,1));
        Dialog ownedDialog=dialog;LinearLayout ownedRoot=root;
        historyScroll.setOnTouchListener((v,event)->{if(event.getActionMasked()==android.view.MotionEvent.ACTION_DOWN)followAnchor=false;return false;});
        historyRows.addOnLayoutChangeListener((v,l,t,r,b,oldL,oldT,oldR,oldB)->{if(followAnchor&&focusedMessage!=null)historyScroll.post(()->{if(followAnchor&&focusedMessage!=null)historyScroll.scrollTo(0,Math.max(0,focusedMessage.getTop()-historyScroll.getHeight()/3));});});
        dialog.setContentView(root);dialog.setOnDismissListener(ignored->{RichMarkdownView.releaseTree(ownedRoot);if(dialog==ownedDialog){stop();hits.clear();messages.clear();selected=null;dialog=null;}});
        dialog.setOnKeyListener((d,key,event)->{
            if(key==KeyEvent.KEYCODE_BACK&&event.getAction()==KeyEvent.ACTION_UP&&selected!=null){back();return true;}return false;
        });
        dialog.show();Window window=dialog.getWindow();
        if(window!=null){window.setLayout(-1,-1);window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);window.setStatusBarColor(ChatUi.BAR);window.setNavigationBarColor(Color.WHITE);}
        input.addTextChangedListener(new TextWatcher(){public void beforeTextChanged(CharSequence s,int start,int count,int after){}public void onTextChanged(CharSequence s,int start,int before,int count){changedQuery(false);}public void afterTextChanged(Editable s){}});
        input.setOnEditorActionListener((v,action,event)->{if(action==EditorInfo.IME_ACTION_SEARCH){changedQuery(true);hideKeyboard();return true;}return false;});
        renderResults();input.requestFocus();input.post(()->{if(showing()&&selected==null)((InputMethodManager)activity.getSystemService(Context.INPUT_METHOD_SERVICE)).showSoftInput(input,InputMethodManager.SHOW_IMPLICIT);});
    }
    void showMessage(MessageApi.Message message,String name){show(message.conversationId,name);open(new MessageApi.SearchHit(message,name));}
    void showQuote(MessageApi.Quote quote,String room,String name){
        try{var value=new org.json.JSONObject().put("id",quote.id).put("clientMessageId","").put("deviceId","").put("sender",quote.sender).put("platform","").put("text",quote.text).put("createdAt",0).put("conversationId",room);showMessage(new MessageApi.Message(value),name);}
        catch(Exception error){session.report(error);}
    }
    void save(Bundle out){if(showing()){out.putBoolean("chatSearch",true);out.putString("chatSearchRoom",room);out.putString("chatSearchTitle",title);out.putString("chatSearchQuery",input.getText().toString());}}
    void restore(Bundle saved){if(saved!=null&&saved.getBoolean("chatSearch")){show(saved.getString("chatSearchRoom"),saved.getString("chatSearchTitle","聊天记录"));input.setText(saved.getString("chatSearchQuery",""));}}
    void changed(){if(showing()&&connection!=session.connectionStamp())dismiss();}
    private boolean showing(){return dialog!=null&&dialog.isShowing();}
    private boolean valid(int stamp){return showing()&&stamp==generation&&connection==session.connectionStamp();}
    private void stop(){generation++;if(debounce!=null)main.removeCallbacks(debounce);if(request!=null)request.cancel(true);busy=false;}
    void dismiss(){stop();if(dialog!=null){Dialog previous=dialog;dialog=null;previous.dismiss();}hits.clear();messages.clear();selected=null;}
    void close(){dismiss();worker.shutdownNow();if(ownsImageActions)imageActions.close();}
    private void hideKeyboard(){((InputMethodManager)activity.getSystemService(Context.INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(input.getWindowToken(),0);input.clearFocus();}
    private void changedQuery(boolean immediate){
        stop();query=input.getText().toString().trim();hits.clear();before=null;hasMore=false;searched=false;error="";
        if(query.length()>100)error="搜索词最多 100 字符";
        if(!query.isEmpty()&&error.isEmpty()){
            busy=true;int stamp=generation;debounce=()->{if(valid(stamp))search(false);};main.postDelayed(debounce,immediate?0:350);
        }
        renderResults();
    }
    private void search(boolean append){
        MessageApi api=session.searchClient();if(api==null)return;
        busy=true;error="";int stamp=generation;String q=query,scope=room;Long cursor=append?before:null;
        renderResults();request=worker.submit(()->{
            try{
                var page=api.search(q,scope,cursor);
                main.post(()->{
                    if(!valid(stamp))return;
                    if(!append)hits.clear();Set<Long> known=new HashSet<>();for(var hit:hits)known.add(hit.message.id);
                    for(var hit:page.results)if(known.add(hit.message.id))hits.add(hit);
                    before=page.nextBefore;hasMore=page.hasMore&&before!=null;searched=true;busy=false;renderResults();
                });
            }catch(Exception failure){main.post(()->{if(valid(stamp)){session.searchFailure(failure);if(!valid(stamp))return;busy=false;error=reason(failure);renderResults();}});}
        });
    }
    private void renderResults(){
        if(results==null)return;int y=resultScroll.getScrollY();results.removeAllViews();
        if(query.isEmpty()){notice(results,"输入关键字，查找文字聊天记录");return;}
        if(!hits.isEmpty())notice(results,"聊天记录 · 已找到 "+hits.size()+" 条"+(hasMore?"，可继续加载":""));
        for(var hit:hits){
            LinearLayout cell=column();cell.setPadding(ui.dp(18),ui.dp(15),ui.dp(18),ui.dp(15));cell.setBackground(ui.ripple(Color.WHITE,0));
            cell.setTag("search-result:"+hit.message.id);cell.setFocusable(true);
            LinearLayout heading=row();TextView name=ui.text(room==null?hit.conversationName:hit.message.sender,16,ChatUi.INK);name.setMaxLines(1);heading.addView(name,new LinearLayout.LayoutParams(0,-2,1));
            TextView date=ui.text(date(hit.message.createdAt),10,ChatUi.MUTED);date.setPadding(ui.dp(8),0,0,0);heading.addView(date);cell.addView(heading);
            if(room==null){TextView sender=ui.text(hit.message.sender,12,ChatUi.MUTED);sender.setPadding(0,ui.dp(5),0,0);cell.addView(sender);}
            TextView excerpt=ui.text("",14,ChatUi.MUTED);excerpt.setText(highlight(excerpt(hit.message.text,query),query));excerpt.setMaxLines(3);excerpt.setPadding(0,ui.dp(7),0,0);cell.addView(excerpt);
            cell.setOnClickListener(v->open(hit));results.addView(cell);results.addView(ui.divider(18));
        }
        if(busy)notice(results,"正在搜索…");
        else if(!error.isEmpty()){
            notice(results,error);Button retry=ui.button("重试");retry.setOnClickListener(v->{if(hits.isEmpty())changedQuery(true);else search(true);});results.addView(retry);
        }else if(searched&&hits.isEmpty())notice(results,"未找到相关聊天记录");
        else if(hasMore){Button more=ui.button("加载更多聊天记录");more.setOnClickListener(v->search(true));results.addView(more);}
        resultScroll.post(()->resultScroll.scrollTo(0,y));
    }
    private void open(MessageApi.SearchHit hit){
        stop();hideKeyboard();focusedMessage=null;followAnchor=false;selected=hit;messages.clear();historyRevision=null;hasOlder=false;hasNewer=false;error="";
        entry.setVisibility(View.GONE);resultScroll.setVisibility(View.GONE);historyBar.setVisibility(View.VISIBLE);historyScroll.setVisibility(View.VISIBLE);
        historyBar.removeAllViews();Button back=ui.button("‹ 搜索结果");back.setOnClickListener(v->back());historyBar.addView(back);
        TextView name=ui.text(hit.conversationName,16,ChatUi.INK);name.setMaxLines(1);name.setGravity(Gravity.CENTER);historyBar.addView(name,new LinearLayout.LayoutParams(0,ui.dp(50),1));
        Button chat=ui.button("进入会话");chat.setOnClickListener(v->{if(messages.isEmpty())return;String id=hit.message.conversationId;dismiss();enter.accept(id);});historyBar.addView(chat);
        loadHistory("around");
    }
    private void back(){stop();selected=null;error="";RichMarkdownView.releaseTree(historyRows);historyRows.removeAllViews();messages.clear();entry.setVisibility(View.VISIBLE);resultScroll.setVisibility(View.VISIBLE);historyBar.setVisibility(View.GONE);historyScroll.setVisibility(View.GONE);renderResults();}
    private void loadHistory(String direction){
        if(busy||selected==null)return;MessageApi api=session.searchClient();if(api==null)return;
        if(!direction.equals("around"))followAnchor=false;
        busy=true;error="";lastDirection=direction;int stamp=generation;String scope=selected.message.conversationId;
        long anchor=direction.equals("before")&&!messages.isEmpty()?messages.get(0).id:direction.equals("after")&&!messages.isEmpty()?messages.get(messages.size()-1).id:selected.message.id;
        renderHistory(false,null);request=worker.submit(()->{
            try{
                var page=api.searchContext(scope,anchor,direction);
                main.post(()->{
                    if(!valid(stamp)||selected==null)return;busy=false;
                    if(historyRevision!=null&&historyRevision!=page.historyRevision){messages.clear();hasOlder=false;hasNewer=false;error="聊天记录已变更，请返回重新搜索。";renderHistory(false,null);return;}
                    historyRevision=page.historyRevision;
                    if(direction.equals("around"))messages.clear();Set<Long> known=new HashSet<>();for(var message:messages)known.add(message.id);
                    for(var message:page.messages)if(known.add(message.id))messages.add(message);messages.sort(Comparator.comparingLong(m->m.id));
                    if(!direction.equals("after"))hasOlder=page.hasOlder;if(!direction.equals("before"))hasNewer=page.hasNewer;
                    renderHistory(direction.equals("around"),direction.equals("before")?anchor:null);
                });
            }catch(Exception failure){main.post(()->{if(valid(stamp)){session.searchFailure(failure);if(!valid(stamp))return;busy=false;error=reason(failure);renderHistory(false,null);}});}
        });
    }
    private void renderHistory(boolean center,Long keepAnchor){
        int y=historyScroll.getScrollY();RichMarkdownView.releaseTree(historyRows);historyRows.removeAllViews();
        if(hasOlder){Button older=ui.button("查看更早的消息");older.setEnabled(!busy);older.setOnClickListener(v->loadHistory("before"));historyRows.addView(older);}
        View target=null,kept=null;
        for(var message:messages){
            LinearLayout cell=column();cell.setPadding(ui.dp(10),ui.dp(12),ui.dp(10),ui.dp(12));
            boolean match=selected!=null&&message.id==selected.message.id;cell.setBackground(ui.shape(match?0xFFE4F5E8:ChatUi.BAR,8));
            TextView sender=ui.text(message.sender+" · "+date(message.createdAt),12,ChatUi.MUTED);sender.setPadding(0,0,0,ui.dp(9));cell.addView(sender);
            if(!message.text.isEmpty()){
                if(RichMarkdownView.isRequired(message.text))cell.addView(new RichMarkdownView(activity,message.text,false),new LinearLayout.LayoutParams(-1,-2));
                else{TextView body=ui.text("",14,ChatUi.INK);new MessageMarkdown(activity).setText(body,message.text,false);body.setTextIsSelectable(true);cell.addView(body);}
                cell.setOnLongClickListener(v->{((android.content.ClipboardManager)activity.getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("消息",message.text));Toast.makeText(activity,"已复制",Toast.LENGTH_SHORT).show();return true;});
            }
            for(String id:message.imageIds){ImageView image=new ImageView(activity);image.setScaleType(ImageView.ScaleType.FIT_CENTER);cell.addView(image,new LinearLayout.LayoutParams(ui.dp(220),ui.dp(165)));session.bindImage(image,id);imageActions.bind(image,id);}
            LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(-1,-2);params.bottomMargin=ui.dp(12);historyRows.addView(cell,params);
            if(match)target=cell;if(keepAnchor!=null&&message.id==keepAnchor)kept=cell;
        }
        if(hasNewer){Button newer=ui.button("查看更新的消息");newer.setEnabled(!busy);newer.setOnClickListener(v->loadHistory("after"));historyRows.addView(newer);}
        if(busy)notice(historyRows,"正在加载聊天记录…");
        if(!error.isEmpty()){notice(historyRows,error);Button retry=ui.button("重试");retry.setOnClickListener(v->loadHistory(messages.isEmpty()?"around":lastDirection));historyRows.addView(retry);}
        focusedMessage=target;if(center)followAnchor=true;
        View anchorView=center?target:kept;
        historyScroll.post(()->{if(anchorView!=null)historyScroll.scrollTo(0,Math.max(0,anchorView.getTop()-(center?historyScroll.getHeight()/3:0)));else historyScroll.scrollTo(0,y);session.refreshImages();});
    }
    private void notice(LinearLayout parent,String value){TextView text=ui.text(value,13,ChatUi.MUTED);text.setGravity(Gravity.CENTER);text.setPadding(ui.dp(20),ui.dp(24),ui.dp(20),ui.dp(24));parent.addView(text,new LinearLayout.LayoutParams(-1,-2));}
    private LinearLayout column(){LinearLayout view=new LinearLayout(activity);view.setOrientation(LinearLayout.VERTICAL);return view;}
    private LinearLayout row(){LinearLayout view=new LinearLayout(activity);view.setOrientation(LinearLayout.HORIZONTAL);return view;}
    private static String reason(Exception failure){return failure.getMessage()==null?"无法读取聊天记录，请重试。":failure.getMessage();}
    private static String date(long value){return DateFormat.getDateTimeInstance(DateFormat.SHORT,DateFormat.SHORT).format(new Date(value));}
    static String excerpt(String body,String query){
        String flat=body.replace('\n',' ').replace('\r',' ');var match=Pattern.compile(Pattern.quote(query),Pattern.CASE_INSENSITIVE|Pattern.UNICODE_CASE).matcher(flat);
        if(query.isEmpty()||!match.find())return flat.substring(0,safeBoundary(flat,Math.min(flat.length(),120)));
        int start=safeBoundary(flat,Math.max(0,match.start()-28)),end=safeBoundary(flat,Math.min(flat.length(),match.end()+80));
        return (start>0?"…":"")+flat.substring(start,end)+(end<flat.length()?"…":"");
    }
    private static int safeBoundary(String text,int index){return index>0&&index<text.length()&&Character.isLowSurrogate(text.charAt(index))&&Character.isHighSurrogate(text.charAt(index-1))?index-1:index;}
    static CharSequence highlight(String text,String query){
        var value=new SpannableString(text);if(query.isEmpty())return value;
        var matches=Pattern.compile(Pattern.quote(query),Pattern.CASE_INSENSITIVE|Pattern.UNICODE_CASE).matcher(text);
        while(matches.find())value.setSpan(new ForegroundColorSpan(ChatUi.GREEN),matches.start(),matches.end(),Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);return value;
    }
}
