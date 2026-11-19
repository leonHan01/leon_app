package com.leon.app;

/** Home tabs are independent from the conversation currently open in the session. */
final class ChatNavigation {
    enum Tab { AGENTS, GROUPS, SETTINGS }
    Tab tab = Tab.AGENTS;
    boolean inChat;
    boolean attachments;

    void tab(Tab selected) { tab=selected; inChat=false; attachments=false; }
    void chat() { inChat=true; attachments=false; }
    boolean back() {
        if (attachments) { attachments=false; return true; }
        if (inChat) { inChat=false; return true; }
        return false;
    }
    void restore(String value, boolean chat) {
        try { tab=Tab.valueOf(value); } catch (IllegalArgumentException | NullPointerException ignored) { tab=Tab.AGENTS; }
        inChat=chat; attachments=false;
    }
}
