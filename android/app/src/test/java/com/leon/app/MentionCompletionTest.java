package com.leon.app;

import org.junit.Test;
import static org.junit.Assert.*;

public class MentionCompletionTest {
    @Test public void detectsBareAtAndFiltersChineseNameOrHandle(){
        assertEquals("",MentionCompletion.token("你好 @",4,4).query);
        assertTrue(MentionCompletion.matches("写作助手","writer","写作"));
        assertTrue(MentionCompletion.matches("写作助手","writer","WRI"));
        assertFalse(MentionCompletion.matches("技术顾问","coder","wri"));
        assertEquals("写",MentionCompletion.token("＠写",2,2).query);
        var adjacent=MentionCompletion.token("你好@写",4,4);
        assertEquals(" @writer ",MentionCompletion.insertion("你好@写",adjacent,"writer"));
    }
    @Test public void ignoresEmailsWhitespaceAndSelections(){
        assertNull(MentionCompletion.token("me@example.com",14,14));
        assertNull(MentionCompletion.token("@writer ",8,8));
        assertNull(MentionCompletion.token("@w",0,2));
        assertNull(MentionCompletion.token("@a.",3,3));
    }
    @Test public void replacesOnlyMentionAtCaretIncludingRemainingSuffix(){
        String text="😀 @wriXYZ 保留";var token=MentionCompletion.token(text,7,7);
        assertEquals(3,token.start);assertEquals(10,token.end);assertEquals("wri",token.query);
        String insert=MentionCompletion.insertion(text,token,"writer");
        assertEquals("😀 @writer 保留",text.substring(0,token.start)+insert+text.substring(token.end));
        assertEquals(11,MentionCompletion.caretAfterInsertion(text,token,insert));
    }
    @Test public void addsSpaceWithoutReplacingOtherMentions(){
        String text="@coder 和 @w";var token=MentionCompletion.token(text,text.length(),text.length());
        String insert=MentionCompletion.insertion(text,token,"writer");
        assertEquals("@coder 和 @writer ",text.substring(0,token.start)+insert+text.substring(token.end));
    }
}
