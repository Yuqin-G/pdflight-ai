// Reference host for the original installed Harness components. This adapter
// intentionally imports no PDFlight preview, zoom hook, stylesheet or model.
import './assets/pdflight-static.js';
const modules = {};
window.__ModuleLoader__ = {load(definition) { modules[definition.id] = definition.factory(name => window.__PD_STATIC__[name]); }};
for (const name of ['chat', 'conversation', 'warm-theme']) await new Promise((resolve, reject) => {
  const script = document.createElement('script'); script.src = name + '.js'; script.onload = resolve; script.onerror = reject; document.head.append(script);
});
const React = window.__PD_STATIC__.react;
const h = React.createElement;
const chat = modules['@deepseek-ai/dsh-client-ui-chat'];
const conversation = modules['@deepseek-ai/dsh-client-ui-conversation'];
modules['@local/claude-warm-theme'].apply({
  effect: callback => callback(),
  theme: {overrideTokens(name, tokens) {
    const query = matchMedia('(prefers-color-scheme: dark)');
    const update = () => {
      document.body.toggleAttribute('data-ds-dark-theme', query.matches);
      for (const [key, value] of Object.entries(tokens)) document.body.style.setProperty(key, query.matches ? value.dark : value.light);
    };
    update(); query.addEventListener('change', update);
    return () => query.removeEventListener('change', update);
  }}
});
const root = window.__PD_STATIC__['react-dom/client'].createRoot(document.getElementById('root'));
let nodes = new Map(), order = [];
const session = {blank: false, awaitingFirstTurn: false, running: false, openState: 'open', openError: null, hasMore: false, loadingOlder: false, pendingSubmissions: []};
const useSession = select => select(session);
const useConversation = select => select({activeTargets: new Set(), views: {grouped: () => undefined}});
const useSessions = select => select({byId: {local: {cwd: ''}}});
const usePresentation = select => select({mode: 'chat', collapseTiming: 'immediate'});
const useChat = select => select({nodes, order, navigation: {items: () => []}});
const useGroupAction = () => React.useRef(null);
const t = (key, values) => Object.entries(values ?? {}).reduce((value, [name, replacement]) => value.replaceAll('{' + name + '}', String(replacement)), chat.locale[key] ?? key);
function renderFactorySlot(name, props) {
  if (name === 'conversation.chat.user.content') return h(chat.UserContent, {...props, renderFactorySlot, renderSlot, t});
  if (name === 'conversation.user.text') return h(conversation.UserText, {...props, useUserTextRevision: select => select(0), createUserTextEvaluator: () => ({text}) => [{id: 'text', start: 0, end: text.length, data: {}}], reportTransformFailure() {}, renderSlot: (name, props, options) => options.fallback});
  return null;
}
const viewProps = {view: 'chat', useSession, useConversation, useConversationViews: select => select([{id: 'chat'}]), useStore: select => select({view: 'chat'}), useInspectCall: select => select(undefined), actions: {setDraft() {}}, inputActions: {persistDraft() {}}, bindDraftPersistence: () => () => {}, openView() {}, renderSlot};
function renderSlot(name, props, options = {}) {
  if (name === 'conversation.session') return h('div', {'data-slot': name, style: {display: 'contents'}}, h(conversation.Views, viewProps));
  if (name === 'conversation.view') return h(chat.ChatView, {useSession, useChat, useConversation, useSessions, renderSlot, sessionId: 'local', openFile: async () => {}, openExternalLink() {}, loadOlder: async () => {}, loadThrough: async () => {}, loadImage: async () => null, inspectCall() {}, chatScroll: {read: () => null, save() {}}, forkAt() {}, fileMentions: () => undefined, usePresentation, useProjection: (key, select) => select?.(undefined), t});
  if (name === 'conversation.chat.node') {
    if (props.node.kind === 'user') return h(chat.User, {...props, renderFactorySlot, loadImage: async () => null, t});
    if (props.node.kind === 'assistant') return h(chat.Assistant, {...props, useDisclosure: () => [false, () => {}], useGroupAction, useTurnData: () => undefined, usePresentation, renderSlot, t, loadImage: async () => null});
  }
  if (name === 'conversation.chat.flow') return h(chat.ChatFlow, {...props, useSession, useChat, useChatNode: key => nodes.get(key), useChatNodeBottom: () => false, useChatNodeProcess: () => undefined, useChatGroup: () => undefined, usePresentation, useStore: select => select({}), actions: {}, renderSlot, renderFactorySlot, t, useGroupAction, useGroupHeaderAction: useGroupAction});
  return options.fallback ?? null;
}
function FixedChatView() { return renderSlot('conversation.session', {view: 'chat'}); }
const contentProps = {sessionId: 'local', variant: 'embedded', phase: 'active', hero: false, useSession, useSessions, useSessionStatus: select => select(new Map()), useWorkspaces: select => select({items: [], phase: 'ready'}), useInput: select => select({draft: ''}), useComposerBlock: select => select(undefined), renderSlot, renderSlotChain: (name, props, options) => options.fallback, selectWorkspace: async () => {}, t, useFactorySlot: (name, fallback) => name === 'views' ? FixedChatView : fallback};
window.PDFlightReplaceMessages = items => {
  order = items.map(item => item.id);
  nodes = new Map(items.map((item, index) => [item.id, {key: item.id, kind: item.role, location: {kind: 'session'}, anchorSeq: index, data: item.role === 'assistant' ? {blocks: [{kind: 'text', text: item.content}], status: 'done'} : {content: [{type: 'text', text: item.content}], time: Date.parse(item.createdAt)}}]));
  root.render(h('div', {className: 'pr-workspace', style: {display: 'flex'}}, h('section', {className: 'pr-chat', style: {flex: 1}}, h('div', {id: 'chat-body', className: 'pr-native-chat'}, h(conversation.Content, contentProps)))));
};
window.__setChatZoom = zoom => { document.getElementById('chat-body').style.zoom = String(zoom); };
window.PDFlightReplaceMessages([]);
