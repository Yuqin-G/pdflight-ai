import './assets/pdflight-static.js';
import { useHarnessChatZoom } from './harness-chat-zoom.js';
const C = {};
window.__ModuleLoader__ = {load(def){C[def.id] = def.factory(name => {if(!(name in window.__PD_STATIC__)) throw new Error('Missing '+name);return window.__PD_STATIC__[name]})}};
for(const name of ['dsh-client-ui-chat','dsh-client-ui-model-selection','dsh-client-ui-conversation']) await new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=name+'.js';s.onload=resolve;s.onerror=reject;document.head.append(s)});
const React=window.__PD_STATIC__.react, root=window.__PD_STATIC__['react-dom/client'].createRoot(document.getElementById('root'));
const chat=C['@deepseek-ai/dsh-client-ui-chat'], conv=C['@deepseek-ai/dsh-client-ui-conversation'];
const data=window.__TEST_MESSAGES__;
const nodes=new Map(data.map((m,i)=>[m.id, {key:m.id,kind:m.role,location:{kind:'session'},anchorSeq:i,data:m.role==='assistant'?{blocks:[{kind:'text',text:m.content}],status:'done'}:{content:[{type:'text',text:m.content}],time:new Date(m.createdAt).getTime()}}]));
const order=[...nodes.keys()], chatData={order,nodes,navigation:{items:()=>[]}};
const session={running:false,openState:'open',openError:null,hasMore:false,loadingOlder:false,pendingSubmissions:[]};
const useSession=f=>f(session), useChat=f=>f(chatData), useConversation=f=>f({views:{grouped:()=>undefined}}),useSessions=f=>f({byId:{local:{cwd:''}}}),usePresentation=f=>f({mode:'chat',collapseTiming:'immediate'}),useProjection=(key,f)=>f?f(undefined):undefined;
const t=(key, values)=>{let v=chat.PDLocale[key]??key;if(values) for(const [k,x] of Object.entries(values))v=v.replaceAll('{'+k+'}',String(x));return v;};
const useGroupAction=()=>React.useRef(null), useStore=f=>f({}), chatScroll={read:()=>null,save:()=>{}};
function renderFactorySlot(name,p) {
 if(name==='conversation.chat.user.content')return React.createElement(chat.PDUserContent,{...p,renderFactorySlot,renderSlot,t});
 if(name==='conversation.user.text')return React.createElement(conv.PDUserText,{...p,useUserTextRevision:f=>f(0),createUserTextEvaluator:()=>({text})=>[{id:'text',start:0,end:text.length,data:{}}],reportTransformFailure:()=>{},renderSlot:(name,p,opts)=>opts.fallback});
 return null;
}
function renderSlot(name,p,options={}) {
 if(name==='conversation.chat.node'){
  if(p.node.kind==='user') return React.createElement(chat.PDUser,{...p,renderFactorySlot,loadImage:async()=>null,t});
  if(p.node.kind==='assistant') return React.createElement(chat.PDAssistant,{...p,useDisclosure:()=>[false,()=>{}],useGroupAction,useTurnData:()=>undefined,usePresentation,renderSlot,t,loadImage:async()=>null});
 }
 if(name==='conversation.chat.flow')return React.createElement(chat.PDChatFlow,{...p,useSession,useChat,useChatNode:key=>nodes.get(key),useChatNodeBottom:()=>false,useChatNodeProcess:()=>undefined,useChatGroup:()=>undefined,usePresentation,useStore,actions:{},renderSlot,renderFactorySlot,t,useGroupAction,useGroupHeaderAction:useGroupAction});
 return options.fallback??null;
}
const props={useSession,useChat,useConversation,useSessions,renderSlot,sessionId:'local',openFile:async()=>{},openExternalLink:()=>{},loadOlder:async()=>{},loadThrough:async()=>{},loadImage:async()=>null,inspectCall:()=>{},chatScroll,forkAt:()=>{},fileMentions:()=>undefined,usePresentation,useProjection,t};

function ChatBody() {
 const ref=React.useRef(null);
 const {applyRef}=useHarnessChatZoom(React,window.__PD_STATIC__['react-dom'].flushSync,ref);
 React.useEffect(()=>{window.__setChatZoom=next=>applyRef.current?.(next);return()=>{delete window.__setChatZoom}},[]);
 return React.createElement('div',{ref,id:'chat-body',className:'pr-native-chat',style:{overflow:'hidden'}},React.createElement(chat.PDChatView,props));
}
root.render(React.createElement(ChatBody));
function apply(next){window.__setChatZoom(next)}
window.__runZoomBenchmark=async()=>{const area=document.getElementById('chat-body');const values=[];apply(1);area.dispatchEvent(new Event('gesturestart',{cancelable:true}));for(let i=0;i<20;i++){let start=performance.now();let event=new Event('gesturechange',{cancelable:true});Object.defineProperty(event,'scale',{value:1+i*.01});area.dispatchEvent(event);area.getBoundingClientRect();values.push(performance.now()-start);await new Promise(r=>setTimeout(r,16));}area.dispatchEvent(new Event('gestureend',{cancelable:true}));return {events:values.length,total:values.reduce((a,b)=>a+b,0),max:Math.max(...values),zoom:area.style.zoom,width:area.getBoundingClientRect().width,viewport:document.documentElement.clientWidth}};

window.__boundsCheck=async()=>{
 const area=document.getElementById('chat-body');
 const scrollers=[...area.querySelectorAll('*')].filter(el=>el.scrollHeight>el.clientHeight+20 && getComputedStyle(el).overflowY!=='visible');
 const scroller=scrollers.sort((a,b)=>b.clientHeight-a.clientHeight)[0];
 if(!scroller)return {error:'no scroll container'};
 const results=[];
 for(const zoom of [0.8,1,1.4,2,2.4]) {
  apply(zoom);
  for(const fraction of [0,.5,1]) {
   scroller.scrollTop=(scroller.scrollHeight-scroller.clientHeight)*fraction;
   await new Promise(r=>setTimeout(r,100));
   const view=scroller.getBoundingClientRect();
   const walker=document.createTreeWalker(scroller,NodeFilter.SHOW_TEXT);
   let node,visible=0,clipped=0;
   while((node=walker.nextNode())) {
    if(!node.nodeValue.trim() || node.parentElement.closest('.katex,pre,code,button,table,[class*="_placeholder"]'))continue;
    const range=document.createRange();range.selectNodeContents(node);
    for(const r of range.getClientRects()) {
     if(r.bottom<=view.top || r.top>=view.bottom || r.width===0)continue;
     visible++;if(r.left<view.left-1 || r.right>view.right+1)clipped++;
    }
   }
   const wideTables=[...scroller.querySelectorAll('.md-table-wide')].filter(t=>t.scrollWidth>t.clientWidth+1);
   let scrollableTables=0;
   for(const table of wideTables) {
    const before=table.scrollLeft;table.scrollLeft=table.scrollWidth;
    if(table.scrollLeft>0)scrollableTables++;table.scrollLeft=before;
   }
   results.push({zoom,fraction,visible,clipped,wideTables:wideTables.length,scrollableTables});
  }
 }
 return results;
};
