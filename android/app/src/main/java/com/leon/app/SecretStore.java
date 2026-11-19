package com.leon.app;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.security.KeyStore;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;

final class SecretStore {
    private static final String ALIAS = "leon-access-token";
    private final SharedPreferences prefs;
    SecretStore(Context context) { prefs = context.getSharedPreferences("connection", Context.MODE_PRIVATE); }
    private javax.crypto.SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias(ALIAS)) return (javax.crypto.SecretKey) store.getKey(ALIAS, null);
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }
    String read() throws Exception {
        String encrypted = prefs.getString("encryptedToken", ""), iv = prefs.getString("tokenIV", "");
        if (encrypted.isEmpty()) return "";
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)));
        return new String(cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP)), java.nio.charset.StandardCharsets.UTF_8);
    }
    void saveSession(String token,String server,MessageApi.User user) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        String encrypted = Base64.encodeToString(cipher.doFinal(token.getBytes(java.nio.charset.StandardCharsets.UTF_8)), Base64.NO_WRAP);
        if (!prefs.edit().putString("encryptedToken", encrypted).putString("tokenIV", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                .putString("server",server).putString("sender",user.username()).putString("chatUserId",user.id()).commit()) throw new java.io.IOException("连接设置保存失败。");
    }
    void clearSession(){
        prefs.edit().remove("encryptedToken").remove("tokenIV").remove("chatUserId").apply();
    }
}
