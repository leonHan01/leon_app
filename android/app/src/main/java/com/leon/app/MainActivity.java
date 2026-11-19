package com.leon.app;

import android.app.*;
import android.os.*;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.*;
import android.view.*;
import android.view.inputmethod.EditorInfo;
import android.widget.*;
import org.json.JSONObject;
import java.text.DateFormat;
import java.util.Date;

public final class MainActivity extends Activity implements ChatSession.Listener {
    private static final int BLUE = Color.rgb(46, 92, 227), INK = Color.rgb(28, 36, 55), MUTED = Color.rgb(112, 122, 140);
    private ChatSession session;
    private MessageMarkdown markdown;
    private TextView status, roomTitle;
    private Button mentionButton;
    private String renderedConversation = "";
    private MentionEditText composer;
    private LinearLayout attachmentRows;
    private Button imageButton;
    private String attachmentSignature = "";
    private LinearLayout mentionPanel, mentionRows;
    private final java.util.List<MessageApi.Agent> mentionCandidates = new java.util.ArrayList<>();
    private int mentionIndex;
    private String mentionKey = "", dismissedMentionKey = "", mentionRenderKey = "";
    private Button send, older;
    private ScrollView scroll;
    private LinearLayout timeline;
    private long renderedRevision = -1;
    private AlertDialog settings;

    @Override public void onCreate(Bundle savedState) {
        super.onCreate(savedState);
        session = (ChatSession) getLastNonConfigurationInstance();
        if (session == null) session = new ChatSession(getApplicationContext());
        session.listener = this;
        markdown = new MessageMarkdown(this);
        buildUI();
        changed();
        if (!session.configured() || savedState != null && savedState.getBoolean("settings")) showSettings();
    }
    @Override public Object onRetainNonConfigurationInstance() { return session; }
    @Override protected void onStart() { super.onStart(); session.start(); }
    @Override protected void onStop() { session.stop(); super.onStop(); }
    @Override protected void onSaveInstanceState(Bundle out) {
        out.putBoolean("settings", settings != null && settings.isShowing()); super.onSaveInstanceState(out);
    }
    @Override protected void onDestroy() {
        session.listener = null;
        if (settings != null) settings.dismiss();
        if (!isChangingConfigurations()) session.close();
        super.onDestroy();
    }

    private void buildUI() {
        LinearLayout root = column(); root.setBackgroundColor(Color.rgb(246, 247, 251));
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
            root.setOnApplyWindowInsetsListener((v, insets) -> {
                android.graphics.Insets edges = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
                v.setPadding(edges.left, edges.top, edges.right, edges.bottom); return insets;
            });
        }
        LinearLayout header = row(); header.setPadding(dp(20), dp(20), dp(12), dp(18)); header.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout title = column();
        TextView brand = text("Leon", 27, INK); brand.setTypeface(null, Typeface.BOLD); title.addView(brand);
        TextView subtitle = text("Agent 私聊 · 群聊协作", 12, MUTED); title.addView(subtitle);
        header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        Button refresh = action("同步"); refresh.setOnClickListener(v -> session.refresh()); header.addView(refresh);
        Button configure = action("设置"); configure.setOnClickListener(v -> showSettings()); header.addView(configure);
        root.addView(header);

        status = text("尚未连接", 12, MUTED); status.setPadding(dp(20), dp(10), dp(20), dp(10));
        status.setBackgroundColor(Color.WHITE); root.addView(status);
        LinearLayout roomBar = column(); roomBar.setPadding(dp(18),dp(12),dp(18),dp(8));
        roomTitle = text(session.title(),19,INK);roomTitle.setTypeface(null,Typeface.BOLD);roomBar.addView(roomTitle);
        LinearLayout roomActions=row();
        Button rooms=action("会话");rooms.setOnClickListener(v->showConversations());roomActions.addView(rooms);
        Button agents=action("Agent 私聊");agents.setOnClickListener(v->showAgents(false));roomActions.addView(agents);
        Button group=action("＋ 群聊");group.setOnClickListener(v->showNewGroup());roomActions.addView(group);
        roomBar.addView(roomActions);root.addView(roomBar);
        scroll = new ScrollView(this); scroll.setFillViewport(true);
        scroll.setOnScrollChangeListener((v,x,y,oldX,oldY)->session.refreshImages());
        timeline = column(); timeline.setPadding(dp(18), dp(12), dp(18), dp(18)); scroll.addView(timeline);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        LinearLayout inputArea = column(); inputArea.setPadding(dp(16), dp(12), dp(16), dp(10)); inputArea.setBackgroundColor(Color.WHITE);
        mentionButton=action("@ Agent");mentionButton.setOnClickListener(v->showAgents(true));
        inputArea.addView(mentionButton);
        imageButton=action("选择图片");imageButton.setOnClickListener(v->{
            android.content.Intent picker=new android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT);
            picker.setType("image/*");picker.addCategory(android.content.Intent.CATEGORY_OPENABLE);
            picker.putExtra(android.content.Intent.EXTRA_ALLOW_MULTIPLE,true);startActivityForResult(picker,42);
        });
        inputArea.addView(imageButton);
        attachmentRows=row();inputArea.addView(attachmentRows);
        mentionPanel=column();mentionPanel.setPadding(dp(6),dp(6),dp(6),dp(6));mentionPanel.setBackground(shape(Color.rgb(246,248,255),12));mentionPanel.setVisibility(View.GONE);
        TextView mentionTitle=text("提及 Agent · ↑↓选择，Enter/Tab 确认，Esc 关闭",10,MUTED);mentionTitle.setPadding(dp(6),dp(3),dp(6),dp(5));mentionPanel.addView(mentionTitle);
        ScrollView mentionScroll=new ScrollView(this);mentionRows=column();mentionScroll.addView(mentionRows);mentionPanel.addView(mentionScroll,new LinearLayout.LayoutParams(-1,dp(120)));inputArea.addView(mentionPanel);
        LinearLayout inputRow = row(); inputRow.setGravity(Gravity.BOTTOM);
        composer = new MentionEditText(this); composer.setTextColor(INK); composer.setTextSize(16); composer.setHint("写点什么，或在群聊中 @Agent…");
        composer.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE | android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        composer.setMinLines(1); composer.setMaxLines(5); composer.setGravity(Gravity.TOP);
        composer.setPadding(dp(12), dp(10), dp(12), dp(10)); composer.setBackground(shape(Color.rgb(246, 247, 251), 14));
        composer.setImeOptions(EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        composer.setText(session.draft);
        composer.imageInput=(uri,release)->session.addImage(uri,release);
        composer.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int a, int c, int f) {}
            public void onTextChanged(CharSequence s, int start, int before, int count) { session.draft = s.toString(); updateSend(); composer.post(MainActivity.this::updateMentionSuggestions); }
            public void afterTextChanged(Editable s) {}
        });
        composer.selectionChanged=this::updateMentionSuggestions;
        composer.setOnFocusChangeListener((v,focused)->updateMentionSuggestions());
        composer.setOnKeyListener((v,key,event)->{
            if(event.getAction()!=KeyEvent.ACTION_DOWN||event.isCtrlPressed()||event.isAltPressed()||event.isMetaPressed()||event.isShiftPressed()||isComposing())return false;
            updateMentionSuggestions();if(mentionPanel.getVisibility()!=View.VISIBLE)return false;
            if(key==KeyEvent.KEYCODE_ESCAPE){hideMentionSuggestions(true);return true;}
            if(mentionCandidates.isEmpty())return false;
            if(key==KeyEvent.KEYCODE_DPAD_DOWN||key==KeyEvent.KEYCODE_DPAD_UP){mentionIndex=(mentionIndex+(key==KeyEvent.KEYCODE_DPAD_DOWN?1:-1)+mentionCandidates.size())%mentionCandidates.size();highlightMention();return true;}
            if(key==KeyEvent.KEYCODE_ENTER||key==KeyEvent.KEYCODE_TAB){chooseMention(mentionIndex);return true;}
            return false;
        });
        inputRow.addView(composer, new LinearLayout.LayoutParams(0, -2, 1));
        send = action("发送 ↑"); send.setTextColor(Color.WHITE); send.setBackground(shape(BLUE, 14));
        LinearLayout.LayoutParams sendParams = new LinearLayout.LayoutParams(dp(82), dp(48)); sendParams.leftMargin = dp(10);
        inputRow.addView(send, sendParams);
        send.setOnClickListener(v -> { if (session.sendDraft(composer.getText().toString())) { composer.setText(""); scroll.post(() -> scroll.fullScroll(View.FOCUS_DOWN)); } });
        inputArea.addView(inputRow);
        TextView hint = text("最多 4 张图片 · 可粘贴图片 · 长按消息复制文字", 10, MUTED); hint.setPadding(0, dp(8), 0, 0); inputArea.addView(hint);
        root.addView(inputArea); setContentView(root);
    }

    @Override public void changed() {
        status.setText(String.format(java.util.Locale.getDefault(), "%s  %s", session.connected ? "●" : "○", session.status));
        status.setTextColor(session.connected ? Color.rgb(39, 125, 91) : MUTED);
        roomTitle.setText(session.title());
        mentionButton.setVisibility(session.selected()!=null&&session.selected().kind.equals("direct")?View.GONE:View.VISIBLE);
        mentionButton.setEnabled(!session.availableAgents().isEmpty());
        if (!composer.getText().toString().equals(session.draft)) { composer.setText(session.draft);composer.setSelection(composer.length()); }
        if(!renderedConversation.equals(session.selectedConversation)){renderedConversation=session.selectedConversation;hideMentionSuggestions(false);dismissedMentionKey="";mentionKey="";renderedRevision=-1;timeline.setTag(null);timeline.removeAllViews();}
        updateSend();
        renderAttachments();
        updateMentionSuggestions();
        if (settings != null && settings.isShowing()) settings.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(!session.configuring);
        if (renderedRevision != session.revision) { renderMessages(); renderedRevision = session.revision; }
        if (older != null) { older.setText(session.loadingOlder ? "正在加载…" : "加载更早的消息"); older.setEnabled(!session.loadingOlder); older.setVisibility(session.hasOlder ? View.VISIBLE : View.GONE); }
    }
    private void updateSend() {
        if (send == null) return;
        int length = composer.getText().length();
        boolean enabled = session.canSend(composer.getText().toString());
        send.setEnabled(enabled); send.setAlpha(enabled ? 1f : .45f);
        composer.setError(length > 8000 ? "消息最多 8,000 字符" : null);
    }
    @Override public void error(String message) {
        if (isFinishing() || isDestroyed()) return;
        new AlertDialog.Builder(this).setTitle("暂未完成").setMessage(message).setPositiveButton("知道了", null).show();
    }

    private void renderMessages() {
        int previousY = scroll.getScrollY();
        int previousHeight = timeline.getHeight();
        boolean nearBottom = timeline.getChildCount() == 0 || previousHeight - scroll.getHeight() - previousY < dp(100);
        Object firstTag = timeline.getTag();
        long firstId = session.messages.isEmpty() ? 0 : session.messages.get(0).id;
        boolean prepended = firstTag instanceof Long && firstId < (Long) firstTag;
        timeline.setTag(firstId); timeline.removeAllViews();
        older = action("加载更早的消息"); older.setOnClickListener(v -> session.older());
        older.setVisibility(session.hasOlder ? View.VISIBLE : View.GONE); timeline.addView(older);
        if (session.messages.isEmpty() && session.currentPending().isEmpty()) {
            LinearLayout empty = column(); empty.setGravity(Gravity.CENTER); empty.setPadding(dp(20), dp(70), dp(20), dp(70));
            TextView icon = text("↔", 60, BLUE); icon.setGravity(Gravity.CENTER); empty.addView(icon);
            TextView label = text("从一句话开始", 21, INK); label.setTypeface(null, Typeface.BOLD); empty.addView(label);
            TextView description = text("选择 Agent 开始私聊，\n或在群聊中 @指定 Agent。", 14, MUTED); description.setGravity(Gravity.CENTER); description.setPadding(0, dp(14), 0, 0); empty.addView(description);
            timeline.addView(empty);
        }
        for (MessageApi.Message m : session.messages) {
            String date = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(new Date(m.createdAt));
            addBubble(m.text, m.sender + (m.role.equals("assistant") ? " · Agent" : ""), date, m.deviceId.equals(session.deviceId), null, m.role.equals("assistant")?m.agentId:null,m.imageIds);
        }
        for (JSONObject m : session.currentPending()) {
            boolean busy = session.sending.contains(m.optString("clientMessageId"));
            addBubble(m.optString("text"), m.optString("sender"), busy ? "发送中…" : "尚未确认送达服务器", true, busy ? null : m,null,ChatSession.imageIds(m));
        }
        for(MessageApi.Job job:session.jobs){
            LinearLayout jobRow=column();jobRow.setPadding(dp(10),dp(8),dp(10),dp(8));
            jobRow.addView(text(job.agentName+" · "+(job.status.equals("FAILED")?job.error:job.status.equals("RUNNING")?"正在回复…":"等待回复…"),12,MUTED));
            if(job.status.equals("FAILED")){Button retry=action("重试回复");retry.setOnClickListener(v->session.retryJob(job));jobRow.addView(retry);}
            timeline.addView(jobRow);
        }
        scroll.post(() -> {
            if (prepended) scroll.scrollTo(0, previousY + timeline.getHeight() - previousHeight);
            else if (nearBottom) scroll.fullScroll(View.FOCUS_DOWN);
            else scroll.scrollTo(0, previousY);
        });
    }
    private void addBubble(String body, String sender, String detail, boolean mine, JSONObject retry,String agentId,java.util.List<String> images) {
        LinearLayout wrapper = column(); wrapper.setGravity(mine ? Gravity.END : Gravity.START);
        LinearLayout.LayoutParams wp = new LinearLayout.LayoutParams(-1, -2); wp.bottomMargin = dp(18);
        wrapper.setPadding(mine ? dp(42) : 0, 0, mine ? 0 : dp(42), 0);
        TextView name = text(sender, 11, MUTED); name.setPadding(dp(4), 0, dp(4), dp(5));
        if(agentId!=null&&!agentId.isEmpty()){LinearLayout identity=row();identity.setGravity(Gravity.CENTER_VERTICAL);identity.addView(avatar(session.avatarFor(agentId),28));identity.addView(name);wrapper.addView(identity);}else wrapper.addView(name);
        for(String id:images){
            ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.FIT_CENTER);image.setPadding(dp(4),dp(4),dp(4),dp(4));image.setBackground(shape(mine?BLUE:Color.WHITE,12));
            LinearLayout.LayoutParams ip=new LinearLayout.LayoutParams(dp(240),dp(180));ip.bottomMargin=dp(6);wrapper.addView(image,ip);session.bindImage(image,id);
            image.setOnClickListener(v->{
                ImageView large=new ImageView(this);large.setScaleType(ImageView.ScaleType.FIT_CENTER);large.setAdjustViewBounds(true);
                session.bindImage(large,id,true);
                new AlertDialog.Builder(this).setTitle("图片预览").setView(large).setPositiveButton("关闭",null).show();
            });
        }
        TextView bubble = text(body, 16, mine ? Color.WHITE : INK);
        bubble.setPadding(dp(15), dp(12), dp(15), dp(12)); bubble.setLineSpacing(dp(3), 1);
        bubble.setBackground(shape(mine ? BLUE : Color.WHITE, 16));
        bubble.setLinkTextColor(mine ? Color.WHITE : BLUE);
        boolean hasTable = markdown.setText(bubble, body, mine);
        bubble.setOnLongClickListener(v -> {
            ((ClipboardManager) getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("消息", body));
            Toast.makeText(this, "已复制", Toast.LENGTH_SHORT).show(); return true;
        });
        // Table spans measure against the TextView width, including table-only messages.
        if(!body.isEmpty())wrapper.addView(bubble, new LinearLayout.LayoutParams(hasTable ? -1 : -2, -2));
        TextView time = text(detail, 10, MUTED); time.setPadding(dp(4), dp(5), dp(4), 0); wrapper.addView(time);
        if (retry != null) { Button button = action("重试发送"); button.setOnClickListener(v -> session.retry(retry)); wrapper.addView(button); }
        timeline.addView(wrapper, wp);
    }

    @Override protected void onActivityResult(int requestCode,int resultCode,android.content.Intent data){
        super.onActivityResult(requestCode,resultCode,data);
        if(requestCode!=42||resultCode!=RESULT_OK||data==null)return;
        if(data.getClipData()!=null){var clip=data.getClipData();for(int i=0;i<Math.min(clip.getItemCount(),5);i++)session.addImage(clip.getItemAt(i).getUri(),()->{});}
        else if(data.getData()!=null)session.addImage(data.getData(),()->{});
    }
    private void renderAttachments(){
        imageButton.setEnabled(session.configured()&&!session.configuring&&session.draftImages.size()+session.preparingImages<4);
        imageButton.setText(session.preparingImages>0?"正在处理图片…":"选择图片");
        String signature=session.selectedConversation+session.draftImages.stream().map(image->image.id).collect(java.util.stream.Collectors.joining());
        if(signature.equals(attachmentSignature))return;attachmentSignature=signature;attachmentRows.removeAllViews();
        for(ChatImage image:session.draftImages){
            LinearLayout item=column();ImageView preview=new ImageView(this);preview.setScaleType(ImageView.ScaleType.FIT_CENTER);
            var options=new android.graphics.BitmapFactory.Options();options.inSampleSize=8;
            preview.setImageBitmap(android.graphics.BitmapFactory.decodeByteArray(image.data,0,image.data.length,options));item.addView(preview,new LinearLayout.LayoutParams(dp(60),dp(48)));
            Button remove=action("移除");remove.setOnClickListener(v->session.removeImage(image.id));item.addView(remove);attachmentRows.addView(item);
        }
    }

    private boolean isComposing(){return android.view.inputmethod.BaseInputConnection.getComposingSpanStart(composer.getText())>=0;}
    private void hideMentionSuggestions(boolean dismiss){
        if(dismiss)dismissedMentionKey=mentionKey;
        if(mentionPanel!=null)mentionPanel.setVisibility(View.GONE);
        boolean direct=session.selected()!=null&&session.selected().kind.equals("direct");
        if(mentionButton!=null)mentionButton.setVisibility(direct?View.GONE:View.VISIBLE);
    }
    private void updateMentionSuggestions(){
        if(composer==null||mentionPanel==null)return;
        MentionCompletion.Token token=composer.hasFocus()&&!isComposing()?MentionCompletion.token(composer.getText().toString(),composer.getSelectionStart(),composer.getSelectionEnd()):null;
        String key=token==null?"":session.selectedConversation+":"+token.signature()+":"+composer.getSelectionStart();
        if(token==null||session.selected()==null||!session.selected().kind.equals("group")||key.equals(dismissedMentionKey)){
            hideMentionSuggestions(false);if(key.isEmpty()){dismissedMentionKey="";mentionKey="";mentionRenderKey="";}return;
        }
        java.util.List<MessageApi.Agent> filtered=new java.util.ArrayList<>();
        for(MessageApi.Agent agent:session.availableAgents())if(MentionCompletion.matches(agent.name,agent.handle,token.query)&&filtered.size()<8)filtered.add(agent);
        if(!key.equals(mentionKey))mentionIndex=0;mentionKey=key;
        StringBuilder signature=new StringBuilder(key);for(MessageApi.Agent agent:filtered)signature.append(agent.id).append(agent.name).append(agent.avatarId);
        if(!signature.toString().equals(mentionRenderKey)){
            mentionRenderKey=signature.toString();mentionCandidates.clear();mentionCandidates.addAll(filtered);mentionRows.removeAllViews();
            if(filtered.isEmpty()){TextView empty=text("没有匹配的 Agent",12,MUTED);empty.setPadding(dp(9),dp(10),dp(9),dp(10));mentionRows.addView(empty);}
            for(int index=0;index<filtered.size();index++){
                MessageApi.Agent agent=filtered.get(index);final int chosen=index;
                LinearLayout option=row();option.setGravity(Gravity.CENTER_VERTICAL);option.setPadding(dp(8),dp(6),dp(8),dp(6));option.setFocusable(false);option.setContentDescription(agent.name+" @"+agent.handle);
                option.addView(avatar(agent.avatarId,30));LinearLayout identity=column();identity.setPadding(dp(9),0,0,0);identity.addView(text(agent.name,13,INK));identity.addView(text("@"+agent.handle,10,MUTED));option.addView(identity);
                option.setOnClickListener(v->chooseMention(chosen));mentionRows.addView(option);
            }
        }
        if(mentionIndex>=mentionCandidates.size())mentionIndex=0;
        mentionPanel.setVisibility(View.VISIBLE);mentionButton.setVisibility(View.GONE);highlightMention();
    }
    private void highlightMention(){
        for(int i=0;i<mentionRows.getChildCount();i++)mentionRows.getChildAt(i).setBackground(shape(i==mentionIndex&&!mentionCandidates.isEmpty()?Color.rgb(228,236,255):Color.TRANSPARENT,8));
        if(!mentionCandidates.isEmpty())mentionRows.getChildAt(mentionIndex).requestRectangleOnScreen(new android.graphics.Rect(0,0,mentionRows.getChildAt(mentionIndex).getWidth(),mentionRows.getChildAt(mentionIndex).getHeight()),true);
    }
    private void chooseMention(int index){
        if(index<0||index>=mentionCandidates.size()||isComposing())return;
        String text=composer.getText().toString();var token=MentionCompletion.token(text,composer.getSelectionStart(),composer.getSelectionEnd());
        MessageApi.Agent agent=mentionCandidates.get(index);boolean eligible=false;for(var available:session.availableAgents())if(available.id.equals(agent.id))eligible=true;
        if(token==null||!eligible||!MentionCompletion.matches(agent.name,agent.handle,token.query))return;
        String insert=MentionCompletion.insertion(text,token,agent.handle);int caret=MentionCompletion.caretAfterInsertion(text,token,insert);composer.getText().replace(token.start,token.end,insert);composer.setSelection(caret);composer.requestFocus();
        hideMentionSuggestions(false);mentionKey="";dismissedMentionKey="";
    }

    private void showConversations() {
        if(session.conversations.isEmpty()){Toast.makeText(this,"连接后显示会话",Toast.LENGTH_SHORT).show();return;}
        java.util.List<MessageApi.Conversation> rooms=new java.util.ArrayList<>(session.conversations);
        String[] labels=new String[rooms.size()];for(int i=0;i<labels.length;i++)labels[i]=(rooms.get(i).kind.equals("direct")?"◉ ":"# ")+rooms.get(i).name;
        new AlertDialog.Builder(this).setTitle("选择会话").setItems(labels,(d,index)->session.select(rooms.get(index).id)).setNegativeButton("取消",null).show();
    }
    private void showAgents(boolean mention) {
        java.util.List<MessageApi.Agent> directory=new java.util.ArrayList<>();
        for(MessageApi.Agent agent:mention?session.availableAgents():session.agents)if(agent.enabled)directory.add(agent);
        if(directory.isEmpty()){Toast.makeText(this,"请先在服务端页面配置并启用 Agent",Toast.LENGTH_LONG).show();return;}
        String[] labels=new String[directory.size()];for(int i=0;i<labels.length;i++)labels[i]=directory.get(i).name+"  @"+directory.get(i).handle;
        ArrayAdapter<MessageApi.Agent> adapter=new ArrayAdapter<MessageApi.Agent>(this,android.R.layout.simple_list_item_1,directory){
            @Override public View getView(int position,View recycled,android.view.ViewGroup parent){
                MessageApi.Agent agent=getItem(position);LinearLayout item=row();item.setGravity(Gravity.CENTER_VERTICAL);item.setPadding(dp(18),dp(10),dp(18),dp(10));
                item.addView(avatar(agent.avatarId,40));LinearLayout identity=column();identity.setPadding(dp(12),0,0,0);identity.addView(text(agent.name,15,INK));identity.addView(text("@"+agent.handle,11,MUTED));item.addView(identity);return item;
            }
        };
        new AlertDialog.Builder(this).setTitle(mention?"@哪位 Agent":"与 Agent 私聊").setAdapter(adapter,(d,index)->{if(mention)session.mention(directory.get(index));else session.openDirect(directory.get(index));}).setNegativeButton("取消",null).show();
    }
    private void showNewGroup() {
        if(!session.configured())return;
        LinearLayout form=column();form.setPadding(dp(24),dp(8),dp(24),0);
        EditText name=field(form,"群名称","",false);
        form.addView(text("选择加入群聊的 Agent（最多 32 个）",12,MUTED));
        java.util.List<CheckBox> boxes=new java.util.ArrayList<>();java.util.List<MessageApi.Agent> directory=new java.util.ArrayList<>();
        for(MessageApi.Agent agent:session.agents)if(agent.enabled){CheckBox box=new CheckBox(this);box.setText(String.format(java.util.Locale.getDefault(),"%s @%s",agent.name,agent.handle));form.addView(box);boxes.add(box);directory.add(agent);}
        ScrollView contents=new ScrollView(this);contents.addView(form);
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle("新建群聊").setView(contents).setNegativeButton("取消",null).setPositiveButton("创建",null).create();
        dialog.setOnShowListener(d->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{
            String title=name.getText().toString().trim();if(title.isEmpty()||title.length()>60){name.setError("名称应为 1–60 字");return;}
            java.util.List<String> ids=new java.util.ArrayList<>();for(int i=0;i<boxes.size();i++)if(boxes.get(i).isChecked())ids.add(directory.get(i).id);
            if(ids.size()>32){Toast.makeText(this,"最多选择 32 个 Agent",Toast.LENGTH_SHORT).show();return;}
            session.group(title,ids);dialog.dismiss();
        }));dialog.show();
    }

    private void showSettings() {
        if (settings != null && settings.isShowing()) return;
        LinearLayout form = column(); form.setPadding(dp(24), dp(8), dp(24), 0);
        TextView intro = text("两端填写相同服务地址与令牌。令牌由 Android 系统密钥库加密保存。", 13, MUTED); form.addView(intro);
        EditText address = field(form, "服务地址", session.server, false);
        address.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_VARIATION_URI);
        EditText token = field(form, "访问令牌", session.token(), true);
        EditText name = field(form, "设备名称", session.sender, false);
        TextView note = text("应用关闭后不会推送；重新打开会同步服务器历史消息。", 12, MUTED); note.setPadding(0, dp(12), 0, 0); form.addView(note);
        ScrollView formScroll = new ScrollView(this); formScroll.addView(form);
        settings = new AlertDialog.Builder(this).setTitle("连接你的设备").setView(formScroll)
                .setNegativeButton("取消", null).setPositiveButton("验证并连接", null).create();
        settings.setOnShowListener(d -> settings.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            session.configure(address.getText().toString(), token.getText().toString(), name.getText().toString(), () -> {
                if (!isDestroyed()) { composer.setText(""); if (settings != null) settings.dismiss(); }
            });
        }));
        settings.show();
        settings.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(!session.configuring);
    }

    private EditText field(LinearLayout form, String label, String value, boolean secret) {
        TextView title = text(label, 12, MUTED); title.setPadding(0, dp(18), 0, dp(4)); form.addView(title);
        EditText edit = new EditText(this); edit.setSingleLine(true); edit.setTextSize(15);
        edit.setInputType(android.text.InputType.TYPE_CLASS_TEXT | (secret ? android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD : android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES));
        if (secret) { edit.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO); edit.setSaveEnabled(false); }
        edit.setText(value); form.addView(edit, new LinearLayout.LayoutParams(-1, -2)); return edit;
    }
    private ImageView avatar(String avatarId,int size){
        ImageView image=new ImageView(this);image.setLayoutParams(new LinearLayout.LayoutParams(dp(size),dp(size)));image.setScaleType(ImageView.ScaleType.FIT_CENTER);
        image.setPadding(dp(2),dp(2),dp(2),dp(2));image.setBackground(shape(Color.rgb(238,242,248),10));image.setClipToOutline(true);image.setContentDescription("Agent 头像");session.bindAvatar(image,avatarId);return image;
    }
    private LinearLayout column() { LinearLayout v = new LinearLayout(this); v.setOrientation(LinearLayout.VERTICAL); return v; }
    private LinearLayout row() { LinearLayout v = new LinearLayout(this); v.setOrientation(LinearLayout.HORIZONTAL); return v; }
    private TextView text(String text, int size, int color) { TextView v = new TextView(this); v.setText(text); v.setTextSize(size); v.setTextColor(color); return v; }
    private Button action(String label) { Button v = new Button(this); v.setText(label); v.setTextSize(13); v.setTextColor(BLUE); v.setAllCaps(false); v.setMinWidth(0); v.setMinimumWidth(0); return v; }
    private GradientDrawable shape(int color, int radius) { GradientDrawable d = new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(radius)); return d; }
    private int dp(int value) { return Math.round(getResources().getDisplayMetrics().density * value); }
}
