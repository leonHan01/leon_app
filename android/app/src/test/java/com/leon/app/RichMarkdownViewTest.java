package com.leon.app;

import android.content.ClipboardManager;
import android.content.Context;
import android.webkit.WebView;
import android.widget.FrameLayout;
import android.widget.TextView;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;
import static org.robolectric.Shadows.shadowOf;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
public class RichMarkdownViewTest {
    @Test public void extensionsRouteToSharedRendererAndBasicMessagesStayNative(){
        for(String source:new String[]{"- [ ] 待办","正文[^1]","术语\n: 定义","![图](https://example.com/a.png)",
                "```java\nclass A {}\n```","> [!NOTE]\n提示","==高亮==","H~2~O","x^2^",":smile:","[[标题]]",
                "<details><summary>折叠</summary>正文</details>","<table><tr><td colspan=2>表格</td></tr></table>"}){
            assertTrue(source,RichMarkdownView.isRequired(source));
        }
        for(String source:new String[]{"你好","**粗体** 和 *斜体*","[网站](https://example.com)","$x_i^2$","\\[x^2\\]"})assertFalse(source,RichMarkdownView.isRequired(source));
    }
    @Test public void sharedRuntimeAndFontsArePackagedAsAssets() throws Exception{
        var assets=RuntimeEnvironment.getApplication().getAssets();
        String shell=new String(assets.open("markdown.html").readAllBytes(),StandardCharsets.UTF_8);
        assertTrue(shell.contains("renderer.js"));assertTrue(shell.contains("connect-src 'none'"));
        for(String file:new String[]{"renderer.js","diagrams.js","katex.min.css","renderer.css","THIRD-PARTY-LICENSES.txt","fonts/KaTeX_Main-Regular.woff2"}){
            try(var input=assets.open(file)){assertTrue(file,input.read()!=-1);}
        }
    }
    @Test public void lazyContainerBridgeAndCleanupPreserveSource() throws Exception{
        var context=RuntimeEnvironment.getApplication();var parent=new FrameLayout(context);
        String source="```java\nString value = \"原文\";\n```";
        var rich=new RichMarkdownView(context,source,false);parent.addView(rich,new FrameLayout.LayoutParams(320,-2));
        assertEquals(1,rich.getChildCount());assertEquals(source,((TextView)rich.getChildAt(0)).getText().toString());
        Method start=RichMarkdownView.class.getDeclaredMethod("startWeb");start.setAccessible(true);start.invoke(rich);
        WebView web=(WebView)rich.getChildAt(1);
        assertTrue(web.getSettings().getJavaScriptEnabled());assertFalse(web.getSettings().getAllowFileAccess());assertFalse(web.getSettings().getAllowContentAccess());
        assertEquals("https://appassets.androidplatform.net/assets/markdown.html",web.getUrl());
        Method receive=RichMarkdownView.class.getDeclaredMethod("receive",String.class);receive.setAccessible(true);
        receive.invoke(rich,new JSONObject().put("type","height").put("height",128).toString());
        assertEquals(Math.round(128*context.getResources().getDisplayMetrics().density),rich.getLayoutParams().height);
        receive.invoke(rich,new JSONObject().put("type","copy").put("text","原始代码\n").toString());
        assertEquals("原始代码\n",((ClipboardManager)context.getSystemService(Context.CLIPBOARD_SERVICE)).getPrimaryClip().getItemAt(0).getText().toString());
        for(String url:new String[]{"javascript:alert(1)","file:///etc/passwd","content://private/file"})receive.invoke(rich,new JSONObject().put("type","open").put("url",url).toString());
        assertNull(shadowOf(context).getNextStartedActivity());
        RichMarkdownView.releaseTree(parent);assertEquals(1,rich.getChildCount());assertNull(web.getParent());
    }
}
