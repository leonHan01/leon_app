package com.leon.app;

import io.noties.markwon.ext.latex.JLatexMathBlock;
import io.noties.markwon.ext.latex.JLatexMathNode;
import io.noties.markwon.inlineparser.InlineProcessor;
import io.noties.markwon.inlineparser.MarkwonInlineParser;
import org.commonmark.node.Block;
import org.commonmark.node.Node;
import org.commonmark.node.Paragraph;
import org.commonmark.node.Text;
import org.commonmark.parser.block.*;

/** Recognize chat LaTeX before Markdown can consume its backslashes and underscores. */
final class MathMarkdown {
    private MathMarkdown() {}

    static MarkwonInlineParser.FactoryBuilder inlineBuilder() {
        var builder = MarkwonInlineParser.factoryBuilderNoDefaults();
        // Backslash math must run before CommonMark's backslash escape processor.
        builder.addInlineProcessor(new MathInlineProcessor('\\'));
        builder.addInlineProcessor(new MathInlineProcessor('$'));
        return builder.includeDefaults();
    }

    private static boolean escaped(String source, int at) {
        int count = 0;
        while (at > 0 && source.charAt(--at) == '\\') count++;
        return count % 2 != 0;
    }

    private static int closing(String source, String delimiter, int from) {
        for (int at = source.indexOf(delimiter, from); at >= 0; at = source.indexOf(delimiter, at + delimiter.length())) {
            if (!escaped(source, at)) return at;
        }
        return -1;
    }

    private static final class MathInlineProcessor extends InlineProcessor {
        private final char trigger;
        MathInlineProcessor(char trigger) { this.trigger = trigger; }
        @Override public char specialCharacter() { return trigger; }

        @Override protected Node parse() {
            String open, close;
            if (trigger == '\\') {
                if (input.startsWith("\\(", index)) { open = "\\("; close = "\\)"; }
                else if (input.startsWith("\\[", index)) { open = "\\["; close = "\\]"; }
                else return null;
            } else {
                open = input.startsWith("$$", index) ? "$$" : "$";
                close = open;
                if (index > 0 && input.charAt(index - 1) == '$') return null;
            }
            int start = index + open.length();
            if (start >= input.length()) return null;
            boolean singleDollar = open.equals("$");
            if (singleDollar && (Character.isWhitespace(input.charAt(start))
                    || index > 0 && Character.isDigit(input.charAt(index - 1)))) return null;
            int end = closing(input, close, start);
            if (end <= start) return null;
            String latex = input.substring(start, end);
            if (latex.trim().isEmpty() || latex.contains("\n\n")) return null;
            if (singleDollar && (latex.indexOf('\n') >= 0
                    || Character.isWhitespace(input.charAt(end - 1))
                    || end + 1 < input.length() && (Character.isDigit(input.charAt(end + 1))
                        || input.charAt(end + 1) == '$'))) return null;
            JLatexMathNode node = new JLatexMathNode();
            node.latex(latex);
            index = end + close.length();
            return node;
        }
    }

    static final class BlockFactory extends AbstractBlockParserFactory {
        @Override public BlockStart tryStart(ParserState state, MatchedBlockParser matched) {
            if (state.getIndent() >= 4) return BlockStart.none();
            String line = state.getLine().toString();
            int start = state.getNextNonSpaceIndex();
            String open;
            if (line.startsWith("\\[", start)) open = "\\[";
            else if (line.startsWith("$$", start) && !line.startsWith("$$$", start)) open = "$$";
            else return BlockStart.none();
            String close = open.equals("$$") ? "$$" : "\\]";
            String rest = line.substring(start + open.length());
            int end = closing(rest, close, 0);
            // Keep trailing prose in its paragraph; the inline parser handles the formula.
            if (end >= 0 && !rest.substring(end + close.length()).trim().isEmpty()) return BlockStart.none();
            return BlockStart.of(new MathBlockParser(open, close, rest, end)).atIndex(line.length());
        }
    }

    private static final class MathBlockParser extends AbstractBlockParser {
        private final JLatexMathBlock block = new JLatexMathBlock();
        private final String close;
        private final StringBuilder latex = new StringBuilder();
        private final StringBuilder raw = new StringBuilder();
        private boolean firstLine = true;
        private boolean complete;

        MathBlockParser(String open, String close, String rest, int end) {
            this.close = close;
            raw.append(open).append(rest);
            complete = end >= 0;
            latex.append(complete ? rest.substring(0, end) : rest);
        }
        @Override public Block getBlock() { return block; }

        @Override public BlockContinue tryContinue(ParserState state) {
            if (complete) return BlockContinue.none();
            String line = state.getLine().subSequence(state.getIndex(), state.getLine().length()).toString();
            int end = closing(line, close, 0);
            if (end >= 0 && line.substring(end + close.length()).trim().isEmpty()) {
                raw.append('\n').append(line);
                latex.append('\n').append(line, 0, end);
                complete = true;
                return BlockContinue.finished();
            }
            return BlockContinue.atIndex(state.getIndex());
        }

        @Override public void addLine(CharSequence line) {
            if (firstLine) { firstLine = false; return; }
            raw.append('\n').append(line);
            latex.append('\n').append(line);
        }

        @Override public void closeBlock() {
            if (complete && !latex.toString().trim().isEmpty()) {
                block.latex(latex.toString().trim());
            } else {
                // An unfinished expression stays readable instead of rendering partial LaTeX.
                Paragraph literal = new Paragraph();
                literal.appendChild(new Text(raw.toString()));
                block.insertBefore(literal);
                block.unlink();
            }
        }
    }
}
