package com.leon.app;

import android.text.Spanned;
import android.widget.TextView;
import io.noties.markwon.Markwon;
import io.noties.markwon.core.spans.StrongEmphasisSpan;
import io.noties.markwon.core.spans.LinkSpan;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
public class MessageMarkdownTest {
    @Test public void chineseSummaryWithColonRendersBoldNextToEnglish() {
        var context=RuntimeEnvironment.getApplication();
        var markdown=new MessageMarkdown(context);
        String source="**一句话总结：**Transformer 通过注意力机制，让文本中的不同位置相互参考，再经过多层加工。";
        for(boolean mine:new boolean[]{false,true}){
            TextView view=new TextView(context);markdown.setText(view,source,mine);
            assertEquals("一句话总结：Transformer 通过注意力机制，让文本中的不同位置相互参考，再经过多层加工。",view.getText().toString());
            Spanned text=(Spanned)view.getText();var spans=text.getSpans(0,text.length(),StrongEmphasisSpan.class);
            assertEquals(1,spans.length);assertEquals(0,text.getSpanStart(spans[0]));assertEquals(6,text.getSpanEnd(spans[0]));
        }
    }
    @Test public void cjkQuotesAndMixedStylesKeepTheirText(){
        var context=RuntimeEnvironment.getApplication();var markdown=new MessageMarkdown(context);
        for(String[] example:new String[][]{
            {"这是**“注意力”**机制","这是“注意力”机制"},
            {"**总结：**中文内容","总结：中文内容"},
            {"**普通粗体** 和 *斜体*","普通粗体 和 斜体"},
            {"**标题：**T 与 **说明：**C","标题：T 与 说明：C"},
            {"原生私有字符 \uE000 与 **总结：**T","原生私有字符 \uE000 与 总结：T"},
            {"&#xE000; 与 **总结：**T","\uE000 与 总结：T"}
        }){
            TextView view=new TextView(context);markdown.setText(view,example[0],false);
            assertEquals(example[1],view.getText().toString());
            Spanned text=(Spanned)view.getText();assertTrue(text.getSpans(0,text.length(),StrongEmphasisSpan.class).length>0);
        }
    }
    @Test public void codeEscapesLinksAndUnclosedMarkupStayLiteral(){
        var context=RuntimeEnvironment.getApplication();var markdown=new MessageMarkdown(context);
        var baseline=Markwon.create(context);
        for(String source:new String[]{
            "`**总结：**T`", "```text\n**总结：**T\n```", "    **总结：**T",
            "\\*\\*总结：\\*\\*T", "**未闭合："
        }){
            TextView expected=new TextView(context);baseline.setMarkdown(expected,source);
            TextView view=new TextView(context);markdown.setText(view,source,false);
            assertEquals(source,expected.getText().toString(),view.getText().toString());
            Spanned text=(Spanned)view.getText();assertEquals(0,text.getSpans(0,text.length(),StrongEmphasisSpan.class).length);
        }
    }
    @Test public void compatibilityCharactersNeverLeakIntoLinkDestinations(){
        var context=RuntimeEnvironment.getApplication();var markdown=new MessageMarkdown(context);
        TextView view=new TextView(context);markdown.setText(view,"[**总结：**T](https://example.com/a：**b**)",false);
        assertEquals("总结：T",view.getText().toString());
        Spanned text=(Spanned)view.getText();var links=text.getSpans(0,text.length(),LinkSpan.class);
        assertEquals(1,links.length);assertEquals("https://example.com/a：**b**",links[0].getLink());
    }
    @Test public void referenceLinksResolveTheirOriginalLabelsAndDestinations(){
        var context=RuntimeEnvironment.getApplication();var markdown=new MessageMarkdown(context);
        for(String source:new String[]{
            "[**总结：**T]\n\n[**总结：**T]: https://example.com/path",
            "[**总结：**T][ref]\n\n[ref]: https://example.com/\uE000"
        }){
            TextView view=new TextView(context);markdown.setText(view,source,false);
            assertEquals("总结：T",view.getText().toString().stripTrailing());
            Spanned text=(Spanned)view.getText();var links=text.getSpans(0,text.length(),LinkSpan.class);
            assertEquals(1,links.length);
            assertEquals(source.endsWith("path")?"https://example.com/path":"https://example.com/\uE000",links[0].getLink());
        }
    }
}
