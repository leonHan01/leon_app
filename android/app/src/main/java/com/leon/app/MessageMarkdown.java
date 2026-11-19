package com.leon.app;

import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.text.util.Linkify;
import android.widget.TextView;
import io.noties.markwon.AbstractMarkwonPlugin;
import io.noties.markwon.Markwon;
import io.noties.markwon.MarkwonConfiguration;
import io.noties.markwon.core.MarkwonTheme;
import io.noties.markwon.movement.MovementMethodPlugin;
import io.noties.markwon.ext.strikethrough.StrikethroughPlugin;
import io.noties.markwon.ext.tables.TableAwareMovementMethod;
import io.noties.markwon.ext.tables.TablePlugin;
import io.noties.markwon.ext.tables.TableTheme;
import io.noties.markwon.linkify.LinkifyPlugin;
import io.noties.markwon.SoftBreakAddsNewLinePlugin;
import org.commonmark.ext.gfm.tables.TableBlock;
import org.commonmark.node.Node;

/** Native TextView rendering. Reuse the parsers across messages and timeline refreshes. */
final class MessageMarkdown {
    private final Markwon incoming;
    private final Markwon outgoing;

    MessageMarkdown(Context context) {
        incoming = renderer(context, false);
        outgoing = renderer(context, true);
    }

    boolean setText(TextView view, String source, boolean mine) {
        Markwon renderer = mine ? outgoing : incoming;
        Node document = renderer.parse(source);
        renderer.setParsedMarkdown(view, renderer.render(document));
        return containsTable(document);
    }

    private static boolean containsTable(Node node) {
        if (node instanceof TableBlock) return true;
        for (Node child = node.getFirstChild(); child != null; child = child.getNext()) {
            if (containsTable(child)) return true;
        }
        return false;
    }

    private static Markwon renderer(Context context, boolean mine) {
        float density = context.getResources().getDisplayMetrics().density;
        int foreground = mine ? Color.WHITE : Color.rgb(28, 36, 55);
        int inset = mine ? 0x22000000 : 0x0E1C2437;
        TableTheme tableTheme = TableTheme.buildWithDefaults(context)
                .tableBorderColor(mine ? 0x66FFFFFF : 0x331C2437)
                .tableBorderWidth(Math.max(1, Math.round(density)))
                .tableCellPadding(Math.round(8 * density))
                .tableHeaderRowBackgroundColor(inset)
                .tableOddRowBackgroundColor(Color.TRANSPARENT)
                .tableEvenRowBackgroundColor(Color.TRANSPARENT)
                .build();
        return Markwon.builder(context)
                .usePlugin(SoftBreakAddsNewLinePlugin.create())
                .usePlugin(StrikethroughPlugin.create())
                .usePlugin(TablePlugin.create(tableTheme))
                .usePlugin(LinkifyPlugin.create(Linkify.WEB_URLS))
                .usePlugin(MovementMethodPlugin.create(TableAwareMovementMethod.create()))
                .usePlugin(new AbstractMarkwonPlugin() {
                    @Override public void configureTheme(MarkwonTheme.Builder builder) {
                        builder.linkColor(mine ? Color.WHITE : Color.rgb(46, 92, 227))
                                .codeTextColor(foreground)
                                .codeBackgroundColor(inset)
                                .blockQuoteColor(mine ? 0x88FFFFFF : 0x663C5A99);
                    }

                    @Override public void configureConfiguration(MarkwonConfiguration.Builder builder) {
                        builder.linkResolver((view, link) -> {
                            Uri uri = Uri.parse(link);
                            String scheme = uri.getScheme();
                            if (!"https".equalsIgnoreCase(scheme) && !"http".equalsIgnoreCase(scheme)
                                    && !"mailto".equalsIgnoreCase(scheme)) return;
                            try {
                                view.getContext().startActivity(new Intent(Intent.ACTION_VIEW, uri));
                            } catch (ActivityNotFoundException ignored) {
                                // An unavailable handler must not interrupt the conversation.
                            }
                        });
                    }
                }).build();
    }
}
