package com.leon.app;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.*;
import android.view.*;
import android.widget.*;

final class ChatUi {
    static final int GREEN=0xFF07B75A, INK=0xFF191919, MUTED=0xFF8A8A8A, LINE=0xFFE7E7E7;
    static final int BAR=0xFFF7F7F7, CHAT=0xFFEDEDED, OUTGOING=0xFFB2EC86;
    private final Context context;
    ChatUi(Context context){this.context=context;}
    int dp(float value){return Math.round(context.getResources().getDisplayMetrics().density*value);}
    TextView text(String value,int size,int color){
        TextView view=new TextView(context);view.setText(value);view.setTextSize(size);view.setTextColor(color);view.setIncludeFontPadding(false);return view;
    }
    GradientDrawable shape(int color,int radius){GradientDrawable shape=new GradientDrawable();shape.setColor(color);shape.setCornerRadius(dp(radius));return shape;}
    RippleDrawable ripple(int color,int radius){return new RippleDrawable(ColorStateList.valueOf(0x15000000),shape(color,radius),shape(Color.WHITE,radius));}
    Button button(String label){
        Button view=new Button(context);view.setText(label);view.setAllCaps(false);view.setTextSize(14);view.setTextColor(GREEN);
        view.setMinWidth(0);view.setMinimumWidth(0);view.setMinHeight(0);view.setMinimumHeight(0);
        view.setPadding(dp(12),dp(8),dp(12),dp(8));view.setBackground(ripple(Color.TRANSPARENT,5));return view;
    }
    Button toolButton(String label,int resource){
        Button view=button(label);view.setStateListAnimator(null);view.setElevation(0);
        view.setTextSize(12);view.setTypeface(Typeface.create("sans-serif",Typeface.NORMAL));
        view.setTextColor(Color.BLACK);
        view.setIncludeFontPadding(false);view.setGravity(Gravity.TOP|Gravity.CENTER_HORIZONTAL);
        view.setMaxLines(2);view.setPadding(dp(1),dp(6),dp(1),dp(8));view.setBackground(ripple(Color.TRANSPARENT,16));
        GradientDrawable badge=shape(Color.WHITE,16);badge.setStroke(dp(1),0xFFE5E8EB);
        Drawable icon=context.getDrawable(resource).mutate();
        icon.setTintList(ColorStateList.valueOf(Color.BLACK));
        LayerDrawable artwork=new LayerDrawable(new Drawable[]{badge,icon});artwork.setLayerInset(1,dp(16),dp(16),dp(16),dp(16));
        artwork.setBounds(0,0,dp(56),dp(56));view.setCompoundDrawables(null,artwork,null,null);view.setCompoundDrawablePadding(dp(10));
        return view;
    }
    ImageButton icon(int resource,String description){
        ImageButton view=new ImageButton(context);view.setImageResource(resource);view.setImageTintList(ColorStateList.valueOf(INK));
        view.setBackground(ripple(Color.TRANSPARENT,22));view.setPadding(dp(11),dp(11),dp(11),dp(11));
        view.setContentDescription(description);view.setLayoutParams(new LinearLayout.LayoutParams(dp(44),dp(44)));return view;
    }
    View divider(int left){View view=new View(context);view.setBackgroundColor(LINE);LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(-1,dp(.5f));params.leftMargin=dp(left);view.setLayoutParams(params);return view;}
    static final class Bubble extends Drawable {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        private final boolean mine;
        private final float density;
        Bubble(boolean mine,int color,float density){this.mine=mine;this.density=density;paint.setColor(color);}
        @Override public void draw(Canvas canvas){
            Rect bounds=getBounds();float tail=4*density, radius=5*density;
            canvas.drawRoundRect(new RectF(bounds.left+(mine?0:tail),bounds.top,bounds.right-(mine?tail:0),bounds.bottom),radius,radius,paint);
            Path triangle=new Path();float edge=mine?bounds.right-tail:bounds.left+tail, tip=mine?bounds.right:bounds.left;
            triangle.moveTo(edge,bounds.top+13*density);triangle.lineTo(tip,bounds.top+17*density);triangle.lineTo(edge,bounds.top+21*density);triangle.close();canvas.drawPath(triangle,paint);
        }
        @Override public void setAlpha(int alpha){paint.setAlpha(alpha);invalidateSelf();}
        @Override public void setColorFilter(ColorFilter filter){paint.setColorFilter(filter);invalidateSelf();}
        @Override public int getOpacity(){return PixelFormat.TRANSLUCENT;}
    }
    Drawable bubble(boolean mine){return new Bubble(mine,mine?OUTGOING:Color.WHITE,context.getResources().getDisplayMetrics().density);}
}
