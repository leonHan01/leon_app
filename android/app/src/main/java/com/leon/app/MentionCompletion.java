package com.leon.app;

import java.util.Locale;
import java.util.regex.Pattern;

final class MentionCompletion {
    private static final Pattern TOKEN=Pattern.compile("(?:^|[^A-Za-z0-9_])([@＠][\\p{L}\\p{N}\\p{M}_-]{0,64})$");
    private static final Pattern SUFFIX=Pattern.compile("^[\\p{L}\\p{N}\\p{M}_-]*");
    static final class Token {
        final int start,end; final String query;
        Token(int start,int end,String query){this.start=start;this.end=end;this.query=query;}
        String signature(){return start+":"+end+":"+query;}
    }
    static Token token(String text,int start,int end){
        if(start<0||start!=end||start>text.length())return null;
        var match=TOKEN.matcher(text.substring(0,start));if(!match.find())return null;
        var suffix=SUFFIX.matcher(text.substring(start));int trailing=suffix.find()?suffix.end():0;
        return new Token(match.start(1),start+trailing,text.substring(match.start(1)+1,start));
    }
    static boolean matches(String name,String handle,String query){
        String needle=query.toLowerCase(Locale.ROOT);
        return name.toLowerCase(Locale.ROOT).contains(needle)||handle.toLowerCase(Locale.ROOT).contains(needle);
    }
    static String insertion(String text,Token token,String handle){
        boolean whitespace=token.end<text.length()&&(Character.isWhitespace(text.codePointAt(token.end))||Character.isSpaceChar(text.codePointAt(token.end)));
        boolean boundary=token.start>0&&(Character.isLetterOrDigit(text.codePointBefore(token.start))||text.charAt(token.start-1)=='_');
        return (boundary?" ":"")+"@"+handle+(whitespace?"":" ");
    }
    static int caretAfterInsertion(String text,Token token,String insertion){
        int whitespace=0;
        if(token.end<text.length()&&(Character.isWhitespace(text.codePointAt(token.end))||Character.isSpaceChar(text.codePointAt(token.end)))){
            whitespace=text.startsWith("\r\n",token.end)?2:Character.charCount(text.codePointAt(token.end));
        }
        return token.start+insertion.length()+whitespace;
    }
}
