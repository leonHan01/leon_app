package com.leon.app;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.pm.ProviderInfo;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.MediaStore;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.shadows.ShadowContentResolver;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.nio.file.Files;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class ChatImageSaverTest {
    private Store provider;
    private android.content.ContentResolver resolver;
    private byte[] jpeg;
    @Before public void prepare() throws Exception {
        var context=RuntimeEnvironment.getApplication();resolver=context.getContentResolver();
        provider=new Store();provider.file=File.createTempFile("leon-image-save-",".jpg",context.getCacheDir());
        var info=new ProviderInfo();info.authority=MediaStore.AUTHORITY;provider.attachInfo(context,info);
        ShadowContentResolver.registerProviderInternal(MediaStore.AUTHORITY,provider);
        Bitmap bitmap=Bitmap.createBitmap(64,32,Bitmap.Config.ARGB_8888);bitmap.eraseColor(android.graphics.Color.BLUE);
        var output=new ByteArrayOutputStream();bitmap.compress(Bitmap.CompressFormat.JPEG,90,output);bitmap.recycle();jpeg=output.toByteArray();
    }
    @Test public void savesAttachmentBytesAndPublishesOnlyAfterTheWriteCompletes() throws Exception {
        var uri=ChatImageSaver.gallery(resolver,jpeg,"Leon-test.jpg");
        assertEquals(provider.uri,uri);assertArrayEquals(jpeg,Files.readAllBytes(provider.file.toPath()));
        assertEquals("image/jpeg",provider.inserted.getAsString(MediaStore.Images.Media.MIME_TYPE));
        assertEquals("Pictures/Leon",provider.inserted.getAsString(MediaStore.Images.Media.RELATIVE_PATH));
        assertEquals(Integer.valueOf(1),provider.inserted.getAsInteger(MediaStore.Images.Media.IS_PENDING));
        assertEquals(Integer.valueOf(0),provider.updated.getAsInteger(MediaStore.Images.Media.IS_PENDING));
        assertEquals(0,provider.deletes);
    }
    @Test public void failedWriteRemovesThePendingGalleryEntry() throws Exception {
        provider.rejectOpen=true;
        assertThrows(java.io.IOException.class,()->ChatImageSaver.gallery(resolver,jpeg,"Leon-failed.jpg"));
        assertEquals(1,provider.deletes);assertNull(provider.updated);
    }
    @Test public void failedPublicationRemovesTheIncompleteGalleryEntry() throws Exception {
        provider.publishResult=0;
        assertThrows(java.io.IOException.class,()->ChatImageSaver.gallery(resolver,jpeg,"Leon-failed.jpg"));
        assertEquals(1,provider.deletes);assertArrayEquals(jpeg,Files.readAllBytes(provider.file.toPath()));
    }
    @Test public void invalidImageNeverCreatesAGalleryEntry() {
        assertThrows(java.io.IOException.class,()->ChatImageSaver.gallery(resolver,new byte[]{1,2,3},"invalid.jpg"));
        assertThrows(java.io.IOException.class,()->ChatImageSaver.gallery(resolver,new byte[1024*1024+1],"large.jpg"));
        assertNull(provider.inserted);assertEquals(0,provider.deletes);
    }
    public static final class Store extends ContentProvider {
        final Uri uri=Uri.parse("content://media/external_primary/images/media/123");
        File file;ContentValues inserted,updated;int deletes,publishResult=1;boolean rejectOpen;
        @Override public boolean onCreate(){return true;}
        @Override public Uri insert(Uri collection,ContentValues values){inserted=new ContentValues(values);return uri;}
        @Override public ParcelFileDescriptor openFile(Uri uri,String mode) throws FileNotFoundException {
            if(rejectOpen)throw new FileNotFoundException("simulated storage failure");
            return ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_WRITE_ONLY|ParcelFileDescriptor.MODE_CREATE|ParcelFileDescriptor.MODE_TRUNCATE);
        }
        @Override public int update(Uri uri,ContentValues values,String selection,String[] args){updated=new ContentValues(values);return publishResult;}
        @Override public int delete(Uri uri,String selection,String[] args){deletes++;return 1;}
        @Override public String getType(Uri uri){return "image/jpeg";}
        @Override public Cursor query(Uri uri,String[] projection,String selection,String[] args,String sort){return null;}
    }
}
