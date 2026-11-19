package com.leon.app;

import java.util.List;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
public class JobDismissalTest {
    private void scope(ChatSession session,String server,String token) throws Exception {
        session.server=server;
        var restore=ChatSession.class.getDeclaredMethod("restorePending",String.class);restore.setAccessible(true);restore.invoke(session,token);
    }
    private MessageApi.Job job(long id,String status,String error) throws Exception {
        return new MessageApi.Job(new JSONObject().put("messageId",id).put("agentId","sol").put("agentName","Sol").put("status",status).put("error",error));
    }
    @Test public void dismissalsSurviveReloadAndAreIsolatedByConnection() throws Exception {
        var context=RuntimeEnvironment.getApplication();
        var first=new ChatSession(context);var reopened=new ChatSession(context);
        try{
            first.prefs.edit().clear().commit();scope(first,"https://first.invalid","test-one");
            var failed=job(1,"FAILED","超时");var other=job(2,"FAILED","超时");var running=job(3,"RUNNING","");
            first.receiveJobs(List.of(failed,other,running));first.dismissJob(failed);first.dismissJob(running);
            assertEquals(List.of(other,running),first.visibleJobs());assertEquals(1,first.dismissedFailureCount());
            first.receiveJobs(List.of(failed,other,running));assertEquals(2,first.visibleJobs().size());
            scope(reopened,"https://first.invalid","test-one");reopened.receiveJobs(List.of(failed));assertTrue(reopened.visibleJobs().isEmpty());
            scope(reopened,"https://second.invalid","test-one");assertEquals(1,reopened.visibleJobs().size());
            scope(reopened,"https://first.invalid","test-two");assertEquals(1,reopened.visibleJobs().size());
            scope(reopened,"https://first.invalid","test-one");assertTrue(reopened.visibleJobs().isEmpty());
            reopened.restoreDismissedJobs();assertEquals(1,reopened.visibleJobs().size());
            scope(first,"https://first.invalid","test-one");assertEquals(3,first.visibleJobs().size());
        }finally{first.close();reopened.close();first.prefs.edit().clear().commit();}
    }
    @Test public void changedErrorsAndRetriedJobsBecomeVisible() throws Exception {
        var session=new ChatSession(RuntimeEnvironment.getApplication());
        try{
            session.prefs.edit().clear().commit();scope(session,"https://retry.invalid","test-token");
            var failed=job(1,"FAILED","超时");session.receiveJobs(List.of(failed));session.dismissJob(failed);
            assertTrue(session.visibleJobs().isEmpty());
            session.receiveJobs(List.of(job(1,"FAILED","服务中断")));assertEquals(1,session.visibleJobs().size());
            session.receiveJobs(List.of(job(1,"PENDING","")));assertEquals(1,session.visibleJobs().size());
            session.receiveJobs(List.of(failed));assertEquals(1,session.visibleJobs().size());
            session.dismissJob(failed);session.select("other-room");session.select("shared");
            assertTrue(session.visibleJobs().isEmpty());assertEquals(1,session.jobs.size());
        }finally{session.close();session.prefs.edit().clear().commit();}
    }
}
