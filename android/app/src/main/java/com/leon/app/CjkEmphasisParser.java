package com.leon.app;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.List;
import org.commonmark.internal.InlineParserImpl;
import org.commonmark.node.*;
import org.commonmark.parser.InlineParser;
import org.commonmark.parser.InlineParserContext;
import org.commonmark.parser.InlineParserFactory;
import io.noties.markwon.ext.latex.JLatexMathNode;
import org.commonmark.parser.delimiter.DelimiterProcessor;

/** Allow CJK punctuation at bold boundaries without changing the saved or displayed text. */
final class CjkEmphasisParser implements InlineParser {
    private final InlineParser delegate;
    private Map<Character,Character> activePunctuation=Map.of();

    // Markwon 4.6.2 pins commonmark 0.13.0; keep its default inline parser and all extensions.
    CjkEmphasisParser(InlineParserContext context){
        this(context,InlineParserImpl::new);
    }

    CjkEmphasisParser(InlineParserContext context,InlineParserFactory factory){
        delegate=factory.create(new InlineParserContext(){
            @Override public List<DelimiterProcessor> getCustomDelimiterProcessors(){return context.getCustomDelimiterProcessors();}
            @Override public LinkReferenceDefinition getLinkReferenceDefinition(String label){
                return context.getLinkReferenceDefinition(restore(label,activePunctuation));
            }
        });
    }

    @Override public void parse(String source,Node parent){
        boolean needsCompatibility=false;
        for(int i=0;i<source.length();i++)if(source.charAt(i)>=128&&punctuation(source.charAt(i))&&besideBold(source,i)){needsCompatibility=true;break;}
        if(!needsCompatibility){delegate.parse(source,parent);return;}
        // Include decoded entities and resolved references when choosing temporary characters.
        // Their text may contain characters not written literally in this inline source.
        Node original=new Paragraph();delegate.parse(source,original);
        StringBuilder occupied=new StringBuilder(source);collectText(original,occupied);
        StringBuilder input=new StringBuilder(source);
        Map<Character,Character> punctuation=new LinkedHashMap<>();
        int next=0xE000;
        for(int i=0;i<source.length();i++){
            char value=source.charAt(i);
            if(value<128||!punctuation(value)||!besideBold(source,i))continue;
            Character replacement=null;
            for(var entry:punctuation.entrySet())if(entry.getValue()==value){replacement=entry.getKey();break;}
            if(replacement==null){
                while(next<=0xF8FF&&occupied.indexOf(String.valueOf((char)next))>=0)next++;
                if(next>0xF8FF)continue;
                replacement=(char)next++;punctuation.put(replacement,value);
            }
            input.setCharAt(i,replacement);
        }
        activePunctuation=punctuation;
        try{delegate.parse(input.toString(),parent);}finally{activePunctuation=Map.of();}
        if(!punctuation.isEmpty())restore(parent,punctuation);
    }

    private static boolean besideBold(String source,int index){
        return index>=2&&source.charAt(index-1)=='*'&&source.charAt(index-2)=='*'
            ||index+2<source.length()&&source.charAt(index+1)=='*'&&source.charAt(index+2)=='*';
    }
    private static boolean punctuation(char value){
        return switch(Character.getType(value)){
            case Character.CONNECTOR_PUNCTUATION,Character.DASH_PUNCTUATION,
                Character.START_PUNCTUATION,Character.END_PUNCTUATION,
                Character.INITIAL_QUOTE_PUNCTUATION,Character.FINAL_QUOTE_PUNCTUATION,
                Character.OTHER_PUNCTUATION -> true;
            default -> false;
        };
    }
    private static String restore(String source,Map<Character,Character> punctuation){
        if(source==null)return null;
        StringBuilder result=new StringBuilder(source);
        for(int i=0;i<result.length();i++){
            Character original=punctuation.get(result.charAt(i));
            if(original!=null)result.setCharAt(i,original);
        }
        return result.toString();
    }
    private static void restore(Node node,Map<Character,Character> punctuation){
        if(node instanceof Text text)text.setLiteral(restore(text.getLiteral(),punctuation));
        else if(node instanceof JLatexMathNode math)math.latex(restore(math.latex(),punctuation));
        else if(node instanceof Code code)code.setLiteral(restore(code.getLiteral(),punctuation));
        else if(node instanceof HtmlInline html)html.setLiteral(restore(html.getLiteral(),punctuation));
        else if(node instanceof Link link){link.setDestination(restore(link.getDestination(),punctuation));link.setTitle(restore(link.getTitle(),punctuation));}
        else if(node instanceof Image image){image.setDestination(restore(image.getDestination(),punctuation));image.setTitle(restore(image.getTitle(),punctuation));}
        for(Node child=node.getFirstChild();child!=null;child=child.getNext())restore(child,punctuation);
    }
    private static void collectText(Node node,StringBuilder text){
        if(node instanceof Text literal)text.append(literal.getLiteral());
        else if(node instanceof JLatexMathNode math)text.append(math.latex());
        else if(node instanceof Code code)text.append(code.getLiteral());
        else if(node instanceof HtmlInline html)text.append(html.getLiteral());
        else if(node instanceof Link link)text.append(link.getDestination()).append(link.getTitle());
        else if(node instanceof Image image)text.append(image.getDestination()).append(image.getTitle());
        for(Node child=node.getFirstChild();child!=null;child=child.getNext())collectText(child,text);
    }
}
