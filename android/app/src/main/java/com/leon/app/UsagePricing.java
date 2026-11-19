package com.leon.app;

import java.util.Locale;
import java.util.Map;
import java.util.HashMap;

/** Current public text-token rates, USD per million, checked 2026-11-19. */
final class UsagePricing {
    record Rate(double lowInput,double highInput,double lowOutput,double highOutput) {}
    record Estimate(double low,double high) {}
    private static final Map<String,Rate> RATES=new HashMap<>();
    static {
        RATES.put("openai:gpt-4o",new Rate(1.25,2.50,10,10));
        RATES.put("openai:gpt-4.1",new Rate(.50,2,8,8));
        RATES.put("openai:gpt-5.1",new Rate(.125,1.25,10,10));
        RATES.put("openai:gpt-5.2",new Rate(.175,1.75,14,14));
        RATES.put("openai:gpt-4o-mini",new Rate(.075,.15,.60,.60));
        RATES.put("openai:gpt-4.1-mini",new Rate(.10,.40,1.60,1.60));
        RATES.put("openai:gpt-5-mini",new Rate(.025,.25,2,2));
        RATES.put("openai:gpt-5.4",new Rate(.25,2.50,15,15));
        RATES.put("openai:gpt-5.4-mini",new Rate(.075,.75,4.50,4.50));
        RATES.put("openai:gpt-6-astra",new Rate(1,10,50,50));
        RATES.put("openai:gpt-6.1-sol",new Rate(.10,2,10,10));
        RATES.put("deepseek:deepseek-flash",new Rate(.003,.30,.60,1.20));
        RATES.put("deepseek:deepseek-v4-pro",new Rate(.022,1.32,1.98,3.96));
    }
    static Estimate estimate(MessageApi.ModelUsage row){
        Rate rate=RATES.get((row.provider+":"+row.model).toLowerCase(Locale.ROOT));
        if(rate==null||row.inputTokens<0||row.outputTokens<0)return null;
        double input=row.inputTokens/1_000_000.0,output=row.outputTokens/1_000_000.0;
        return new Estimate(input*rate.lowInput+output*rate.lowOutput,input*rate.highInput+output*rate.highOutput);
    }
    private static String money(double value){return value>0&&value<.0001?"<$0.0001":String.format(Locale.US,"$%.4f",value);}
    static String label(Estimate value){return money(value.low)+" – "+money(value.high);}
}
