package com.leon.app;

import android.text.Spanned;
import android.widget.TextView;
import io.noties.markwon.core.spans.LinkSpan;
import io.noties.markwon.core.spans.StrongEmphasisSpan;
import io.noties.markwon.image.AsyncDrawableSpan;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import ru.noties.jlatexmath.JLatexMathDrawable;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public class MathMarkdownTest {
    private Spanned render(String source, boolean mine) {
        TextView view = new TextView(RuntimeEnvironment.getApplication());
        new MessageMarkdown(view.getContext()).setText(view, source, mine);
        return (Spanned) view.getText();
    }

    private AsyncDrawableSpan[] formulas(Spanned text) {
        var spans = text.getSpans(0, text.length(), AsyncDrawableSpan.class);
        java.util.Arrays.sort(spans, java.util.Comparator.comparingInt(text::getSpanStart));
        return spans;
    }

    @Test @GraphicsMode(GraphicsMode.Mode.NATIVE)
    public void attentionFormulaKeepsLatexIntactAndProducesDrawable() {
        String latex = "\\text{Attention}(Q,K,V)\n=\\text{softmax}\\left(\\frac{QK^T}{\\sqrt{d_k}}\\right)V";
        for (boolean mine : new boolean[]{false, true}) {
            Spanned text = render("这个过程通常写成：\n\\[\n" + latex + "\n\\]\n\n**总结：**计算相关性", mine);
            var spans = formulas(text);
            assertEquals(1, spans.length);
            assertEquals(latex, spans[0].getDrawable().getDestination());
            assertEquals(1, text.getSpans(0, text.length(), StrongEmphasisSpan.class).length);
            assertFalse(text.toString().contains("\\["));
            var drawable = JLatexMathDrawable.builder(spans[0].getDrawable().getDestination()).textSize(28).build();
            assertTrue(drawable.getIntrinsicWidth() > 0);
            assertTrue(drawable.getIntrinsicHeight() > 0);
            var bitmap = android.graphics.Bitmap.createBitmap(drawable.getIntrinsicWidth(),
                    drawable.getIntrinsicHeight(), android.graphics.Bitmap.Config.ARGB_8888);
            drawable.setBounds(0, 0, bitmap.getWidth(), bitmap.getHeight());
            drawable.draw(new android.graphics.Canvas(bitmap));
            boolean hasInk = false;
            for (int y = 0; y < bitmap.getHeight() && !hasInk; y++) {
                for (int x = 0; x < bitmap.getWidth(); x++) {
                    if (android.graphics.Color.alpha(bitmap.getPixel(x, y)) > 0) { hasInk = true; break; }
                }
            }
            assertTrue("Formula drawable must paint visible pixels", hasInk);
            bitmap.recycle();
        }
    }

    @Test public void allDelimitersWorkInMessagesListsQuotesAndTables() {
        for (String source : new String[]{
                "行内 $x_i^2$ 和 \\(\\frac{a}{b}\\)",
                "$$\nx_i^2\n$$\n\n\\[\\frac{a}{b}\\]",
                "$$x_i^2$$\n\n\\[\n\\frac{a}{b}\n\\]",
                "> \\[\n> x_i^2\n> \\]\n\n- \\(\\frac{a}{b}\\)"
        }) {
            Spanned text = render(source, false);
            var spans = formulas(text);
            assertEquals(source, 2, spans.length);
            assertEquals("x_i^2", spans[0].getDrawable().getDestination());
            assertEquals("\\frac{a}{b}", spans[1].getDrawable().getDestination());
        }
    }

    @Test public void tableCellsContainMathNodes() {
        String source = "| 数学 |\n| --- |\n| $x_i^2$ 和 \\(\\frac{a}{b}\\) |";
        var parser = org.commonmark.parser.Parser.builder()
                .extensions(java.util.List.of(org.commonmark.ext.gfm.tables.TablesExtension.create()))
                .inlineParserFactory(context -> new CjkEmphasisParser(context, MathMarkdown.inlineBuilder().build()))
                .build();
        java.util.List<String> latex = new java.util.ArrayList<>();
        parser.parse(source).accept(new org.commonmark.node.AbstractVisitor() {
            @Override public void visit(org.commonmark.node.CustomNode node) {
                if (node instanceof io.noties.markwon.ext.latex.JLatexMathNode math) latex.add(math.latex());
                visitChildren(node);
            }
        });
        assertEquals(java.util.List.of("x_i^2", "\\frac{a}{b}"), latex);
        Spanned rendered = render(source, false);
        assertEquals(2, rendered.getSpans(0, rendered.length(), io.noties.markwon.ext.tables.TableRowSpan.class).length);
    }

    @Test public void codeCurrencyEscapesAndUnclosedMathStayReadable() {
        for (String source : new String[]{
                "`$x_i$` 和 `\\(x\\)`", "`` $x_i$ ` \\(x\\) ``",
                "```latex\n\\[\nx_i^2\n\\]\n$$x$$\n```", "    $$x_i^2$$",
                "价格 $5 和 $10，预算 US$20。", "转义 \\$x\\$ 与 \\\\(x\\\\)",
                "未闭合 $x_i", "\\[\nx_i^2", "$$\nx_i^2"
        }) {
            Spanned text = render(source, false);
            assertEquals(source, 0, formulas(text).length);
            assertFalse(text.toString().isEmpty());
        }
        assertEquals("\\[\nx_i^2", render("\\[\nx_i^2", false).toString());
        assertEquals("$$\nx_i^2", render("$$\nx_i^2", false).toString());
    }

    @Test public void markdownAndLinkTargetsKeepTheirMeaning() {
        Spanned text = render("**公式：**T $x_i$，~~删除~~ [网站](https://example.com/$x$)", false);
        assertEquals(1, formulas(text).length);
        assertEquals(1, text.getSpans(0, text.length(), StrongEmphasisSpan.class).length);
        var links = text.getSpans(0, text.length(), LinkSpan.class);
        assertEquals(1, links.length);
        assertEquals("https://example.com/$x$", links[0].getLink());
        Spanned punctuation = render("**公式：**$\\text{**总结：**T} + x$", false);
        assertEquals("\\text{**总结：**T} + x", formulas(punctuation)[0].getDrawable().getDestination());
    }

    @Test public void invalidLatexKeepsSourceAndFollowingParagraph() {
        Spanned text = render("\\[\\unknownLeonCommand{x}\\]\n\n后续消息", false);
        assertEquals(1, formulas(text).length);
        assertTrue(text.toString().contains("\\unknownLeonCommand{x}"));
        assertTrue(text.toString().endsWith("后续消息"));
    }
}
