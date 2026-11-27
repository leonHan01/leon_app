package com.leon.app;

import android.content.Context;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import androidx.recyclerview.widget.DiffUtil;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

/** Recycles message rows and restores the reading anchor independently of row heights. */
final class ChatTimelineView extends RecyclerView {
    record Row(String key, long messageId, Object content, Supplier<View> createView) {
        Row(String key, Object content, Supplier<View> createView) {
            this(key, 0, content, createView);
        }
    }

    private final LinearLayoutManager layout;
    private final TimelineAdapter rows = new TimelineAdapter();
    private boolean followingLatest = true;
    private boolean positioning;
    private boolean waitingForAnchor;
    private boolean alignmentScheduled;
    private ChatSession.ScrollPosition readingPosition;

    ChatTimelineView(Context context, Runnable scrolled) {
        super(context);
        layout = new LinearLayoutManager(context);
        setLayoutManager(layout);
        setAdapter(rows);
        setItemAnimator(null);
        addOnScrollListener(new OnScrollListener() {
            @Override public void onScrollStateChanged(RecyclerView view, int state) {
                if (state == SCROLL_STATE_DRAGGING) pauseFollowing();
                else if (state == SCROLL_STATE_IDLE) scheduleAlignment();
            }

            @Override public void onScrolled(RecyclerView view, int dx, int dy) {
                if (!positioning && dy != 0) {
                    View tail = layout.findViewByPosition(rows.getItemCount() - 1);
                    followingLatest = tail != null
                            && layout.getDecoratedBottom(tail) - (getHeight() - getPaddingBottom()) < dp(48);
                    waitingForAnchor = false;
                    readingPosition = followingLatest ? null : firstVisibleAnchor();
                }
                scrolled.run();
            }
        });
    }

    void enter(ChatSession.ScrollPosition position) {
        stopScroll();
        followingLatest = position == null;
        waitingForAnchor = position != null;
        readingPosition = position;
        positioning = false;
    }

    void submitRows(List<Row> updated, boolean reset, boolean historyLoaded) {
        rows.submit(updated, reset);
        restore(historyLoaded);
    }

    void restore(boolean historyLoaded) {
        if (followingLatest) {
            scheduleAlignment();
        } else if (readingPosition != null && rows.getItemCount() > 0) {
            int position = rows.position(readingPosition.rowKey);
            if (position < 0 && !historyLoaded) return;
            waitingForAnchor = false;
            positioning = true;
            int index = position >= 0 ? position : Math.min(readingPosition.itemPosition, rows.getItemCount() - 1);
            layout.scrollToPositionWithOffset(index, readingPosition.top);
            if (position < 0) readingPosition = null;
        }
    }

    void followLatest() {
        followingLatest = true;
        waitingForAnchor = false;
        readingPosition = null;
        scheduleAlignment();
    }

    void pauseFollowing() {
        if (followingLatest) readingPosition = firstVisibleAnchor();
        followingLatest = false;
        waitingForAnchor = false;
        positioning = false;
    }

    ChatSession.ScrollPosition savedPosition() {
        return followingLatest ? null : readingPosition;
    }

    private ChatSession.ScrollPosition firstVisibleAnchor() {
        ChatSession.ScrollPosition fallback = null;
        for (int i = 0; i < getChildCount(); i++) {
            View child = getChildAt(i);
            int position = getChildAdapterPosition(child);
            if (position == NO_POSITION || layout.getDecoratedBottom(child) <= getPaddingTop()
                    || layout.getDecoratedTop(child) >= getHeight() - getPaddingBottom()) continue;
            Row row = rows.items.get(position);
            var anchor = new ChatSession.ScrollPosition(row.messageId(), layout.getDecoratedTop(child) - getPaddingTop(), position, row.key());
            if (row.messageId() > 0) return anchor;
            if (fallback == null) fallback = anchor;
        }
        return fallback;
    }

    @Override protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        super.onLayout(changed, left, top, right, bottom);
        positioning = false;
        if (!followingLatest && !waitingForAnchor && readingPosition == null) readingPosition = firstVisibleAnchor();
        scheduleAlignment();
    }

    private void scheduleAlignment() {
        if (alignmentScheduled || !isShown()) return;
        alignmentScheduled = true;
        postOnAnimation(() -> {
            alignmentScheduled = false;
            if (!isShown() || rows.getItemCount() == 0 || getHeight() == 0 || isLayoutRequested()
                    || getScrollState() != SCROLL_STATE_IDLE) return;
            int delta;
            if (followingLatest) {
                int last = rows.getItemCount() - 1;
                View tail = layout.findViewByPosition(last);
                if (tail == null) {
                    layout.scrollToPosition(last);
                    return;
                }
                delta = Math.max(0, layout.getDecoratedBottom(tail) - (getHeight() - getPaddingBottom()));
            } else {
                if (waitingForAnchor || readingPosition == null) return;
                View anchor = layout.findViewByPosition(rows.position(readingPosition.rowKey));
                if (anchor == null) return;
                delta = layout.getDecoratedTop(anchor) - getPaddingTop() - readingPosition.top;
            }
            if (delta == 0) return;
            positioning = true;
            scrollBy(0, delta);
            positioning = false;
        });
    }

    @Override public boolean onGenericMotionEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_SCROLL) pauseFollowing();
        return super.onGenericMotionEvent(event);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static final class Holder extends RecyclerView.ViewHolder {
        final FrameLayout container;
        Holder(FrameLayout container) {
            super(container);
            this.container = container;
        }
        void clear() {
            RichMarkdownView.releaseTree(container);
            container.removeAllViews();
        }
    }

    private static final class TimelineAdapter extends RecyclerView.Adapter<Holder> {
        private List<Row> items = List.of();
        private Map<String, Integer> positions = Map.of();
        private Map<String, Long> ids = Map.of();
        private long nextId;

        TimelineAdapter() { setHasStableIds(true); }

        int position(String key) { return positions.getOrDefault(key, NO_POSITION); }
        @Override public int getItemCount() { return items.size(); }
        @Override public long getItemId(int position) { return ids.get(items.get(position).key()); }

        void submit(List<Row> updated, boolean reset) {
            List<Row> previous = items;
            Map<String, Integer> newPositions = new HashMap<>();
            Map<String, Long> newIds = new HashMap<>();
            for (int i = 0; i < updated.size(); i++) {
                String key = updated.get(i).key();
                Long oldId = reset ? null : ids.get(key);
                newPositions.put(key, i);
                newIds.put(key, oldId != null ? oldId : nextId++);
            }
            items = updated;
            positions = newPositions;
            ids = newIds;
            if (reset) {
                notifyDataSetChanged();
                return;
            }
            DiffUtil.calculateDiff(new DiffUtil.Callback() {
                @Override public int getOldListSize() { return previous.size(); }
                @Override public int getNewListSize() { return updated.size(); }
                @Override public boolean areItemsTheSame(int oldIndex, int newIndex) {
                    return previous.get(oldIndex).key().equals(updated.get(newIndex).key());
                }
                @Override public boolean areContentsTheSame(int oldIndex, int newIndex) {
                    return previous.get(oldIndex).content().equals(updated.get(newIndex).content());
                }
            }, false).dispatchUpdatesTo(this);
        }

        @Override public Holder onCreateViewHolder(ViewGroup parent, int type) {
            FrameLayout container = new FrameLayout(parent.getContext());
            container.setLayoutParams(new RecyclerView.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT));
            return new Holder(container);
        }

        @Override public void onBindViewHolder(Holder holder, int position) {
            holder.clear();
            View view = items.get(position).createView().get();
            if (view.getLayoutParams() == null) {
                view.setLayoutParams(new FrameLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT));
            }
            holder.container.addView(view);
        }

        @Override public void onViewRecycled(Holder holder) { holder.clear(); }
    }
}
