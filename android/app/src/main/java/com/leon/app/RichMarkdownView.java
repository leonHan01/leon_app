package com.leon.app;

import android.annotation.SuppressLint;
import android.content.*;
import android.graphics.Color;
import android.graphics.Rect;
import android.net.Uri;
import android.view.*;
import android.webkit.*;
import android.widget.*;
import androidx.webkit.WebViewAssetLoader;
import java.io.ByteArrayInputStream;
import java.util.regex.Pattern;
import org.json.JSONObject;

/** Mac and Android share an offline extension renderer; offscreen bubbles stay lightweight. */
@SuppressLint("ViewConstructor") // Programmatic message content, never inflated from XML.
final class RichMarkdownView extends FrameLayout {
    private static final String PAGE = "https://appassets.androidplatform.net/assets/markdown.html";
    private static final Pattern EXTENDED = Pattern.compile("(?m)```|~~~|!\\[|<[/!A-Za-z]|\\[\\^|\\[\\[|\\[![A-Za-z]+\\]|==[^=\\n]+==|\\^[^\\s^]+\\^|(?:^|[^~])~[^~\\s]+~(?:[^~]|$)|:[+\\w-]+:|^\\s*:\\s+|[-+*]\\s+\\[[ xX]\\]|\\d+[.)]\\s+\\[[ xX]\\]|\\\\(?:newcommand|renewcommand|def|tag|begin\\{aligned)");
    static boolean isRequired(String source) { return EXTENDED.matcher(source).find(); }
    private final String source;
    private Runnable messageAction;
    void setMessageAction(Runnable action){messageAction=action;}
    private void longPress(){if(messageAction!=null)messageAction.run();else copy(source);}
    private final boolean mine;
    private final TextView fallback;
    private WebView web;
    private boolean ready, disposed;
    private int contentHeight;
    private final ViewTreeObserver.OnScrollChangedListener visibilityListener = this::updateVisibility;
    private final Runnable unload = this::stopWeb;

    RichMarkdownView(Context context, String source, boolean mine) {
        super(context); this.source=source; this.mine=mine;
        fallback=new TextView(context); fallback.setText(source); fallback.setTextSize(14); fallback.setTextColor(ChatUi.INK);
        fallback.setPadding(dp(12),dp(10),dp(12),dp(10)); addView(fallback,new LayoutParams(-1,-2));
        setOnLongClickListener(v->{longPress();return true;}); fallback.setOnLongClickListener(v->{longPress();return true;});
    }
    @Override protected void onAttachedToWindow(){super.onAttachedToWindow();getViewTreeObserver().addOnScrollChangedListener(visibilityListener);post(this::updateVisibility);}
    @Override protected void onDetachedFromWindow(){getViewTreeObserver().removeOnScrollChangedListener(visibilityListener);removeCallbacks(unload);stopWeb();super.onDetachedFromWindow();}
    @Override protected void onSizeChanged(int w,int h,int ow,int oh){super.onSizeChanged(w,h,ow,oh);post(this::updateVisibility);}
    @Override protected void onVisibilityChanged(View changed,int visibility){super.onVisibilityChanged(changed,visibility);if(fallback!=null)post(this::updateVisibility);}
    private void updateVisibility(){
        if(disposed||!isAttachedToWindow())return;
        Rect visible=new Rect();
        if(isShown()&&getGlobalVisibleRect(visible)&&visible.height()>0){removeCallbacks(unload);if(web==null)startWeb();}
        else if(web!=null){removeCallbacks(unload);postDelayed(unload,1500);}
    }
    @SuppressLint({"SetJavaScriptEnabled","AddJavascriptInterface","ClickableViewAccessibility"})
    private void startWeb(){
        if(disposed||web!=null)return;
        WebView view=new WebView(getContext());web=view;ready=false;
        view.setBackgroundColor(Color.TRANSPARENT);view.setVerticalScrollBarEnabled(false);view.setHorizontalScrollBarEnabled(false);
        WebSettings settings=view.getSettings();settings.setJavaScriptEnabled(true);settings.setAllowFileAccess(false);settings.setAllowContentAccess(false);
        settings.setAllowFileAccessFromFileURLs(false);settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setDomStorageEnabled(false);settings.setSupportZoom(false);
        settings.setTextZoom(Math.round(100*getResources().getDisplayMetrics().scaledDensity/getResources().getDisplayMetrics().density));
        CookieManager.getInstance().setAcceptThirdPartyCookies(view,false);
        var assets=new WebViewAssetLoader.Builder().addPathHandler("/assets/",new WebViewAssetLoader.AssetsPathHandler(getContext())).build();
        view.addJavascriptInterface(new Bridge(view),"LeonBridge");
        view.setWebViewClient(new WebViewClient(){
            @Override public WebResourceResponse shouldInterceptRequest(WebView v,WebResourceRequest request){
                Uri url=request.getUrl();
                if("appassets.androidplatform.net".equals(url.getHost())&&"https".equals(url.getScheme())){
                    var result=assets.shouldInterceptRequest(url);return result!=null?result:blocked();
                }
                // The document CSP permits external HTTPS images only, without message credentials.
                if(!request.isForMainFrame()&&"https".equals(url.getScheme()))return null;
                return blocked();
            }
            @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest request){
                if(PAGE.equals(request.getUrl().toString()))return false;
                if(request.hasGesture())open(request.getUrl().toString());return true;
            }
            @Override public void onPageFinished(WebView v,String url){if(v==web&&PAGE.equals(url)){ready=true;render();}}
        });
        view.setOnLongClickListener(v->{longPress();return true;});
        view.setOnTouchListener(new OnTouchListener(){float x,y;
            @Override public boolean onTouch(View v,MotionEvent event){
                if(event.getActionMasked()==MotionEvent.ACTION_DOWN){x=event.getX();y=event.getY();}
                if(event.getActionMasked()==MotionEvent.ACTION_MOVE&&Math.abs(event.getX()-x)>Math.abs(event.getY()-y)+dp(8))v.getParent().requestDisallowInterceptTouchEvent(true);
                return false;
            }
        });
        addView(view,new LayoutParams(-1,contentHeight>0?contentHeight:Math.max(dp(48),getHeight())));view.setVisibility(INVISIBLE);view.loadUrl(PAGE);
    }
    private static WebResourceResponse blocked(){return new WebResourceResponse("text/plain","UTF-8",new ByteArrayInputStream(new byte[0]));}
    private void render(){
        if(!ready||web==null||disposed)return;
        try{var payload=new JSONObject().put("source",source).put("mine",mine).put("dark",false).put("platform","android");web.evaluateJavascript("void window.renderMessage("+payload+")",null);}
        catch(Exception ignored){/* Keep the original text readable. */}
    }
    private final class Bridge{
        private final WebView owner;
        Bridge(WebView owner){this.owner=owner;}
        @JavascriptInterface public void postMessage(String value){if(value!=null&&value.length()<=100_000)post(()->{if(!disposed&&web==owner)receive(value);});}
    }
    private void receive(String value){
        try{var event=new JSONObject(value);
            switch(event.optString("type")){
                case "ready":ready=true;render();break;
                case "height":
                    double logical=event.optDouble("height",48);if(!Double.isFinite(logical))break;
                    int next=dp((float)Math.min(200_000,Math.max(24,logical)));ScrollView scroll=parentScroll();
                    boolean bottom=scroll!=null&&scroll.getChildCount()>0&&scroll.getScrollY()+scroll.getHeight()>=scroll.getChildAt(0).getHeight()-dp(60);
                    if(next!=contentHeight){contentHeight=next;web.getLayoutParams().height=next;web.requestLayout();getLayoutParams().height=next;requestLayout();if(bottom)post(()->scroll.fullScroll(View.FOCUS_DOWN));}
                    fallback.setVisibility(GONE);web.setVisibility(VISIBLE);break;
                case "copy":copy(event.optString("text"));break;
                case "open":open(event.optString("url"));break;
                case "anchor":double y=event.optDouble("y",0);if(Double.isFinite(y)){int offset=dp((float)Math.max(0,y));requestRectangleOnScreen(new Rect(0,offset,dp(1),offset+dp(28)),false);}break;
                case "notice":Toast.makeText(getContext(),event.optString("text"),Toast.LENGTH_SHORT).show();break;
                default:break;
            }
        }catch(Exception ignored){/* Ignore malformed bridge events. */}
    }
    private ScrollView parentScroll(){ViewParent parent=getParent();while(parent!=null){if(parent instanceof ScrollView scroll)return scroll;parent=parent.getParent();}return null;}
    private void open(String value){Uri uri=Uri.parse(value);String scheme=uri.getScheme();if(!"http".equalsIgnoreCase(scheme)&&!"https".equalsIgnoreCase(scheme)&&!"mailto".equalsIgnoreCase(scheme))return;try{getContext().startActivity(new Intent(Intent.ACTION_VIEW,uri));}catch(ActivityNotFoundException ignored){}}
    private void copy(String text){((ClipboardManager)getContext().getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("消息",text));Toast.makeText(getContext(),"已复制",Toast.LENGTH_SHORT).show();}
    private int dp(float value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private void stopWeb(){ready=false;if(web==null)return;WebView old=web;web=null;old.stopLoading();old.removeJavascriptInterface("LeonBridge");removeView(old);old.destroy();fallback.setVisibility(VISIBLE);}
    static void releaseTree(View view){if(view instanceof RichMarkdownView rich){rich.disposed=true;rich.removeCallbacks(rich.unload);rich.stopWeb();}else if(view instanceof ViewGroup group)for(int i=0;i<group.getChildCount();i++)releaseTree(group.getChildAt(i));}
}
