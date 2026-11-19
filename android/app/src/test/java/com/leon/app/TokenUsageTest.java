package com.leon.app;

import java.net.ServerSocket;
import java.net.InetAddress;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
public class TokenUsageTest {
    @Test public void authenticatedUsagePreservesLargeTotalsEmptyStateAndUpgradeErrors() throws Exception {
        var server=new ServerSocket(0,5,InetAddress.getByName("127.0.0.1"));
        server.setSoTimeout(10000);
        var worker=java.util.concurrent.Executors.newSingleThreadExecutor();
        var authorization=new AtomicReference<String>();
        var response=new AtomicReference<>("[{\"provider\":\"openai\",\"model\":\"test-model\",\"inputTokens\":3000000000,\"outputTokens\":20,\"totalTokens\":3000000020,\"reportedCalls\":2,\"unreportedCalls\":1}]");
        var status=new java.util.concurrent.atomic.AtomicInteger(200);
        var served=worker.submit(()->{
            for(int i=0;i<5;i++)try(var socket=server.accept()){
                socket.setSoTimeout(10000);
                var input=new BufferedReader(new InputStreamReader(socket.getInputStream(),StandardCharsets.US_ASCII));
                assertEquals("GET /api/agents/usage HTTP/1.1",input.readLine());
                String line;
                while((line=input.readLine())!=null&&!line.isEmpty())
                    if(line.startsWith("Authorization: "))authorization.set(line.substring(15));
                byte[] body=response.get().getBytes(StandardCharsets.UTF_8);
                var output=socket.getOutputStream();
                output.write(("HTTP/1.1 "+status.get()+" Test\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "+body.length+"\r\n\r\n").getBytes(StandardCharsets.US_ASCII));
                output.write(body);output.flush();
            }
            return null;
        });
        try {
            var api=new MessageApi("http://127.0.0.1:"+server.getLocalPort(),"usage-test-token");
            var rows=api.usage();assertEquals("Bearer usage-test-token",authorization.get());
            assertEquals(1,rows.size());assertEquals(3_000_000_020L,rows.get(0).totalTokens);
            assertEquals(1,rows.get(0).unreportedCalls);
            response.set("[]");assertTrue(api.usage().isEmpty());
            status.set(404);assertTrue(assertThrows(Exception.class,api::usage).getMessage().contains("Token 用量"));
            status.set(401);assertTrue(assertThrows(Exception.class,api::usage).getMessage().contains("令牌"));
            status.set(403);assertTrue(assertThrows(Exception.class,api::usage).getMessage().contains("权限"));
            served.get(10,java.util.concurrent.TimeUnit.SECONDS);
        } finally { server.close();worker.shutdownNow(); }
    }
}
