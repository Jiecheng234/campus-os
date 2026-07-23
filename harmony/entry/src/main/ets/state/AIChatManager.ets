import { Conversation, ChatMessage, AIProviderConfig, AIMemory, ToolTrace } from '../domain/AIAgentTypes';
import { StateManager } from './StateManager';
import { generateUUID } from '../utils/CryptoUtils';

export class AIChatManager {
  static createConversation(providerConfig?: AIProviderConfig): Conversation {
    const conv: Conversation = new Conversation();
    conv.id = generateUUID();
    conv.title = 'New Conversation';
    conv.createdAt = new Date().toISOString();
    conv.updatedAt = conv.createdAt;
    if (providerConfig !== undefined) {
      conv.providerConfig = providerConfig;
    }
    StateManager.conversations = [conv].concat(StateManager.conversations);
    StateManager.activeConversationId = conv.id;
    return conv;
  }

  static deleteConversation(id: string): void {
    const kept: Conversation[] = [];
    for (let i: number = 0; i < StateManager.conversations.length; i++) {
      if (StateManager.conversations[i].id !== id) {
        kept.push(StateManager.conversations[i]);
      }
    }
    StateManager.conversations = kept;
    if (StateManager.activeConversationId === id) {
      StateManager.activeConversationId = kept.length > 0 ? kept[0].id : '';
    }
  }

  static getActiveConversation(): Conversation | undefined {
    for (let i: number = 0; i < StateManager.conversations.length; i++) {
      if (StateManager.conversations[i].id === StateManager.activeConversationId) {
        return StateManager.conversations[i];
      }
    }
    return undefined;
  }

  static addMessage(conversationId: string, role: string, content: string): ChatMessage {
    const msg: ChatMessage = new ChatMessage();
    msg.id = generateUUID();
    msg.role = role;
    msg.content = content;
    msg.timestamp = new Date().toISOString();
    for (let i: number = 0; i < StateManager.conversations.length; i++) {
      if (StateManager.conversations[i].id === conversationId) {
        StateManager.conversations[i].messages.push(msg);
        StateManager.conversations[i].updatedAt = msg.timestamp;
        break;
      }
    }
    return msg;
  }

  static updateLastMessage(conversationId: string, content: string): void {
    for (let i: number = 0; i < StateManager.conversations.length; i++) {
      if (StateManager.conversations[i].id === conversationId) {
        const msgs: ChatMessage[] = StateManager.conversations[i].messages;
        if (msgs.length > 0) {
          msgs[msgs.length - 1].content = content;
        }
        break;
      }
    }
  }

  static getConversations(): Conversation[] {
    return StateManager.conversations;
  }

  static setActiveConversation(id: string): void {
    StateManager.activeConversationId = id;
  }
}
