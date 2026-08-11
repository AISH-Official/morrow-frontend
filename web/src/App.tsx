import{FormEvent,useEffect,useMemo,useRef,useState}from'react';
import{Activity,Archive,BarChart3,BrainCircuit,Check,ChevronRight,Command,Footprints,HeartPulse,History,LockKeyhole,LogOut,Mic,MicOff,MoonStar,Plus,RefreshCw,Send,Settings2,ShieldCheck,Signal,Sparkles,ThumbsDown,Trash2,Volume2,VolumeX,Watch,X}from'lucide-react';
import{ApiRequestError,addPersonalMemory,applyDemoScenario,clearAssistantConversation,clearWellnessData,completeRecoveryAttempt,createCheckIn,createRecoveryAttempt,deleteAccountCompletely,exportAccountData,getAiHealthConsent,getConnectedDevices,getDashboard,getPersonalization,getStoredWebSession,getWeeklyReport,isSessionExpired,loginWebSession,logoutWebSession,pairWebSession,rebuildPersonalization,revokeConnectedDevice,sendAssistantMessage,setAiHealthConsent,submitRecommendationFeedback}from'./api';
import type{DemoScenario,RecoveryAction}from'./api';
import type{WebSession}from'./api';
import type{ConnectedDevice}from'./api';
import type{CheckInCause,CheckInInput,CheckInStatus,ConnectionMode,Dashboard,PersonalizationProfile,TimelineItem,TimelineKind,UserMemory,WeeklyReport}from'./types';

type Role='ai'|'user';
type Phase='idle'|'listening'|'thinking'|'speaking';
type ViewKey='today'|'timeline'|'report'|'data'|'settings';
type Chat={id:number;role:Role;text:string};
type RecognitionEvent={results:ArrayLike<{0:{transcript:string};isFinal:boolean}>};
type RecognitionLike={lang:string;continuous:boolean;interimResults:boolean;start:()=>void;stop:()=>void;onresult:((event:RecognitionEvent)=>void)|null;onend:(()=>void)|null;onerror:(()=>void)|null};

const suggestions=['오늘 컨디션 어때?','잠을 잘 못 잤어','집중할 수 있게 도와줘'];
const statusOptions:[CheckInStatus,string,string][]=[['OK','괜찮아요','안정적인 상태'],['TIRED','피곤해요','에너지가 부족함'],['TENSE','긴장돼요','몸과 마음이 굳음'],['LOW_FOCUS','집중이 안 돼요','생각이 흐릿함'],['UNCOMFORTABLE','불편해요','몸이 편하지 않음']];
const causeOptions:[CheckInCause,string][]=[['SLEEP','수면'],['WORK','업무'],['STUDY','학업'],['RELATIONSHIP','관계'],['PHYSICAL','신체'],['UNKNOWN','잘 모르겠어요']];
const statusLabel:Record<string,string>={OK:'괜찮음',TENSE:'긴장',TIRED:'피로',LOW_FOCUS:'집중 저하',UNCOMFORTABLE:'불편함'};
const causeLabel:Record<string,string>={SLEEP:'수면',WORK:'업무',STUDY:'학업',RELATIONSHIP:'관계',PHYSICAL:'신체',UNKNOWN:'복합 요인'};
const welcomeChats:Chat[]=[
 {id:1,role:'ai',text:'안녕하세요, 사용자님.'},
 {id:2,role:'ai',text:'오늘의 건강 흐름과 지금 느끼는 상태를 함께 살펴볼게요.'}
];
const CACHE_PREFIX='morrow.web.state.v1:';
type CachedWebState={dashboard?:Dashboard;report?:WeeklyReport;personalization?:PersonalizationProfile;memories?:UserMemory[];view?:ViewKey;aiMode?:'LIVE'|'FALLBACK'|'LOCAL'|'UNKNOWN';updatedAt?:string};

function readCachedState(userId:string):CachedWebState|null{
 try{const value=window.localStorage.getItem(`${CACHE_PREFIX}${userId}`);if(!value)return null;const parsed=JSON.parse(value) as CachedWebState&{chats?:unknown};delete parsed.chats;if((parsed.view as string)==='privacy')parsed.view='data';return parsed}catch{return null}
}
function updateCachedState(userId:string,patch:Partial<CachedWebState>){
 const current=readCachedState(userId)??{};
 window.localStorage.setItem(`${CACHE_PREFIX}${userId}`,JSON.stringify({...current,...patch,updatedAt:new Date().toISOString()}));
}
function clearCachedState(userId:string){window.localStorage.removeItem(`${CACHE_PREFIX}${userId}`)}

const bootSession=getStoredWebSession();
const bootCache=bootSession?readCachedState(bootSession.userId):null;

export default function App(){
 const[dashboard,setDashboard]=useState<Dashboard|null>(bootCache?.dashboard??null);
 const[report,setReport]=useState<WeeklyReport|null>(bootCache?.report??null);
 const[mode,setMode]=useState<ConnectionMode>(bootCache?'offline':'live');
 const[view,setView]=useState<ViewKey>(bootCache?.view??'today');
 const[message,setMessage]=useState('');
 const[phase,setPhase]=useState<Phase>('idle');
 const[sound,setSound]=useState(false);
 const[chats,setChats]=useState<Chat[]>(welcomeChats);
 const[checkInOpen,setCheckInOpen]=useState(false);
 const[recoveryOpen,setRecoveryOpen]=useState(false);
 const[demoOpen,setDemoOpen]=useState(false);
 const[toast,setToast]=useState('');
 const[feedbackDone,setFeedbackDone]=useState(false);
 const[refreshing,setRefreshing]=useState(false);
 const[personalization,setPersonalization]=useState<PersonalizationProfile|null>(bootCache?.personalization??null);
 const[memories,setMemories]=useState<UserMemory[]>(bootCache?.memories??[]);
 const[devices,setDevices]=useState<ConnectedDevice[]>([]);
 const[aiHealthConsent,setAIHealthConsent]=useState(false);
 const[aiMode,setAiMode]=useState<'LIVE'|'FALLBACK'|'LOCAL'|'UNKNOWN'>(bootCache?.aiMode??'UNKNOWN');
 const[account,setAccount]=useState<WebSession|null>(bootSession);
 const[loginRequired,setLoginRequired]=useState(bootSession===null);
 const[loginMessage,setLoginMessage]=useState(bootSession?'':'데이터를 안전하게 불러오려면 로그인해 주세요.');
 const[loadError,setLoadError]=useState('');
 const recognition=useRef<RecognitionLike|null>(null);
 const nextId=useRef(3);
 const particles=useMemo(()=>Array.from({length:34},(_,index)=>({left:`${(index*47)%100}%`,top:`${(index*71)%100}%`,delay:`-${(index%13)*.37}s`,size:1+(index%3)})),[]);

 useEffect(()=>{if(bootSession)void loadData();return()=>{recognition.current?.stop();window.speechSynthesis?.cancel()}},[]);
 useEffect(()=>{if(!toast)return;const timer=window.setTimeout(()=>setToast(''),2800);return()=>window.clearTimeout(timer)},[toast]);
 useEffect(()=>{if(account)updateCachedState(account.userId,{dashboard:dashboard??undefined,report:report??undefined,personalization:personalization??undefined,memories,view,aiMode})},[account,dashboard,report,personalization,memories,view,aiMode]);

 async function loadData(showSpinner=false){
  if(showSpinner)setRefreshing(true);
  try{
   const[dashResult,weekly,personal,connected,consent]=await Promise.all([getDashboard(),getWeeklyReport(),getPersonalization(),getConnectedDevices(),getAiHealthConsent()]);
   setDashboard(dashResult);setMode('live');setReport(weekly);setPersonalization(personal.profile);setMemories(personal.memories);setDevices(connected);setAIHealthConsent(consent);setLoadError('');
   const session=getStoredWebSession();if(session)updateCachedState(session.userId,{dashboard:dashResult,report:weekly,personalization:personal.profile,memories:personal.memories});
   return true;
  }catch(error){
   if(isSessionExpired(error)){expireSession();return false}
   setMode('offline');setLoadError('서버에서 최신 데이터를 불러오지 못했습니다.');
   if(dashboard)setToast('연결이 불안정해 마지막으로 저장된 데이터를 보여드려요.');
   return false;
  }finally{setRefreshing(false)}
 }

 function expireSession(){
  setAccount(null);setLoginRequired(true);setLoginMessage('로그인이 만료되었습니다. 다시 로그인해 주세요.');setLoadError('');
 }

 function hydrateAccount(value:WebSession){
  const cached=readCachedState(value.userId);
  setDashboard(cached?.dashboard??null);setReport(cached?.report??null);setPersonalization(cached?.personalization??null);setMemories(cached?.memories??[]);setDevices([]);setChats(welcomeChats);setView(cached?.view??'today');setAiMode(cached?.aiMode??'UNKNOWN');setMode(cached?'offline':'live');setLoadError('');
 }

 function speak(text:string){
  if(!sound||!('speechSynthesis'in window)){setPhase('idle');return}
  const utterance=new SpeechSynthesisUtterance(text);utterance.lang='ko-KR';utterance.rate=.98;utterance.pitch=.96;utterance.onend=()=>setPhase('idle');utterance.onerror=()=>setPhase('idle');window.speechSynthesis.cancel();window.speechSynthesis.speak(utterance);
 }

 function streamAnswer(answer:string){
  const id=nextId.current++;setChats(value=>[...value,{id,role:'ai',text:''}]);setPhase('speaking');let index=0;
  const timer=window.setInterval(()=>{index+=1;setChats(value=>value.map(item=>item.id===id?{...item,text:answer.slice(0,index)}:item));if(index>=answer.length){window.clearInterval(timer);speak(answer)}},14);
 }

 async function send(text=message){
  const clean=text.trim();if(!clean||phase==='thinking'||phase==='speaking')return;
  recognition.current?.stop();window.speechSynthesis?.cancel();setChats(value=>[...value,{id:nextId.current++,role:'user',text:clean}]);setMessage('');setPhase('thinking');
  try{const result=await sendAssistantMessage(clean);setAiMode(result.aiMode);if(result.personalized)setPersonalization(value=>value?{...value,evidenceCount:Math.max(value.evidenceCount,result.personalizationEvidenceCount),personalized:true}:value);streamAnswer(result.content)}
  catch(error){setPhase('idle');if(isSessionExpired(error))expireSession();else setToast('AI 연결을 확인한 뒤 다시 시도해 주세요.')}
 }

 function toggleMic(){
  if(phase==='listening'){recognition.current?.stop();setPhase('idle');return}
  const target=window as typeof window&{webkitSpeechRecognition?:new()=>RecognitionLike;SpeechRecognition?:new()=>RecognitionLike};
  const Constructor=target.SpeechRecognition||target.webkitSpeechRecognition;
  if(!Constructor){setToast('이 브라우저는 음성 입력을 지원하지 않아요.');return}
  const instance=new Constructor();instance.lang='ko-KR';instance.continuous=false;instance.interimResults=true;
  instance.onresult=event=>{let value='';for(let index=0;index<event.results.length;index++)value+=event.results[index][0].transcript;setMessage(value)};
  instance.onend=()=>setPhase(value=>value==='listening'?'idle':value);instance.onerror=()=>{setPhase('idle');setToast('음성 입력을 시작하지 못했어요.')};
  recognition.current=instance;setPhase('listening');instance.start();
 }

 function newSession(){
  window.speechSynthesis?.cancel();setPhase('idle');setMessage('');setChats([{id:nextId.current++,role:'ai',text:'새로운 대화를 시작했어요. 지금 가장 신경 쓰이는 상태를 알려주세요.'}]);setToast('새 세션을 시작했어요.');
 }

 async function forgetConversation(){
  try{await clearAssistantConversation();setChats([{id:nextId.current++,role:'ai',text:'이전 대화 기억을 삭제했어요. 새롭게 이야기해 주세요.'}]);setToast('AI의 이전 대화 기억을 삭제했어요.')}catch(error){if(isSessionExpired(error))expireSession();else setToast('대화 기억을 삭제하지 못했습니다. 다시 시도해 주세요.')}
 }
 async function revokeDevice(id:string){try{await revokeConnectedDevice(id);setDevices(await getConnectedDevices());setToast('선택한 기기의 연결을 해제했어요.')}catch(error){if(isSessionExpired(error))expireSession();else setToast('기기 연결을 해제하지 못했습니다.')}}
 async function changeAIHealthConsent(value:boolean){try{setAIHealthConsent(await setAiHealthConsent(value));setToast(value?'AI 건강 데이터 사용을 허용했어요.':'AI 답변에서 건강 데이터 사용을 중지했어요.')}catch(error){if(isSessionExpired(error))expireSession();else setToast('AI 데이터 설정을 바꾸지 못했습니다.')}}

 async function saveCheckIn(input:CheckInInput){
  try{await createCheckIn(input);await loadData();setCheckInOpen(false);setFeedbackDone(false);setToast('체크인이 저장되어 모든 기기 흐름에 반영됐어요.')}
  catch(error){if(isSessionExpired(error))expireSession();else{setMode('offline');setToast('체크인을 저장하지 못했습니다. 연결을 확인하고 다시 시도해 주세요.')}}
 }

 async function feedback(helpful:boolean){
  if(!dashboard?.recommendation)return;
  try{await submitRecommendationFeedback(dashboard.recommendation.id,helpful);const personal=await getPersonalization();setPersonalization(personal.profile);setMemories(personal.memories)}catch(error){if(isSessionExpired(error))expireSession();else{setMode('offline');setToast('피드백을 저장하지 못했습니다.');}return}
  setFeedbackDone(true);setToast(helpful?'좋아요. 이 회복 방법을 더 잘 기억할게요.':'알겠어요. 다음에는 다른 방법을 제안할게요.');
  const now=new Date();
  const recovery:TimelineItem={id:`feedback-${Date.now()}`,time:now.toLocaleTimeString('ko-KR',{hour:'2-digit',minute:'2-digit',hour12:false}),title:'회복 활동 피드백',detail:helpful?'짧은 걷기가 도움이 됐어요.':'이번 추천은 도움이 되지 않았어요.',kind:'recovery',userConfirmed:true};
  setDashboard(value=>value?{...value,timeline:[...value.timeline,recovery]}:value);
 }

 async function deleteData(){
  if(!window.confirm('모든 기기의 웰니스 기록과 AI 기억을 삭제할까요? 삭제 후 복구할 수 없습니다.'))return;
  try{await clearWellnessData();await loadData();setToast('서버의 웰니스 기록과 개인화 메모리를 삭제했어요.')}catch(error){if(isSessionExpired(error))expireSession();else setToast('데이터를 삭제하지 못했습니다. 연결을 확인해 주세요.')}
 }
 async function deleteAccount(){
  if(!window.confirm('계정과 모든 기록을 완전히 삭제할까요? 이 작업은 복구할 수 없습니다.'))return;
  try{await deleteAccountCompletely();if(account)clearCachedState(account.userId);window.localStorage.removeItem('morrow.web.session.v2');setAccount(null);setDashboard(null);setReport(null);setLoginRequired(true);setLoginMessage('계정과 모든 기록을 삭제했습니다.')}catch(error){if(isSessionExpired(error))expireSession();else setToast('계정을 삭제하지 못했습니다.')}
 }
 async function downloadData(){try{const data=await exportAccountData();const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));const link=document.createElement('a');link.href=url;link.download=`morrow-data-${new Date().toISOString().slice(0,10)}.json`;link.click();URL.revokeObjectURL(url);setToast('내 데이터 파일을 내려받았어요.')}catch(error){if(isSessionExpired(error))expireSession();else setToast('데이터를 내려받지 못했습니다.')}}

 async function rebuildLearning(){try{await rebuildPersonalization();const personal=await getPersonalization();setPersonalization(personal.profile);setMemories(personal.memories);setToast('전체 기록에서 개인화 메모리를 다시 학습했어요.')}catch(error){if(isSessionExpired(error))expireSession();else setToast('백엔드에 연결한 뒤 다시 시도해 주세요.')}}
 async function addMemory(type:'PREFERENCE'|'GOAL',summary:string){try{await addPersonalMemory(type,summary);const personal=await getPersonalization();setPersonalization(personal.profile);setMemories(personal.memories);setToast('직접 알려준 내용을 개인화 메모리에 저장했어요.')}catch(error){if(isSessionExpired(error))expireSession();else setToast('메모리를 저장하지 못했어요.')}}
 async function loadDemoScenario(scenario:DemoScenario){
  try{const result=await applyDemoScenario(scenario);if(account)clearCachedState(account.userId);await loadData(true);setChats([{id:nextId.current++,role:'ai',text:`${result.title} 시나리오를 준비했어요. 오늘의 회복 신호와 주간 리포트에서 감지 근거와 실제 효과를 확인해 보세요.`}]);setDemoOpen(false);setView('today');setToast('심사용 데모 데이터를 적용했어요.')}catch(error){if(isSessionExpired(error))expireSession();else setToast('데모 시나리오를 준비하지 못했어요.')}}
 async function connectPhoneAccount(code:string){
  const previousUserId=account?.userId;const value=await pairWebSession(code);
  if(previousUserId&&previousUserId!==value.userId)clearCachedState(previousUserId);
  clearCachedState(value.userId);setAccount(value);setDashboard(null);setReport(null);setPersonalization(null);setMemories([]);setChats(welcomeChats);setAiMode('UNKNOWN');setMode('live');setView('today');setLoadError('');setLoginMessage('');setLoginRequired(false);
  return{value,loaded:await loadData(true)};
 }
 async function pairAccount(code:string){try{const{value,loaded}=await connectPhoneAccount(code);setToast(loaded?`이 아이디를 iPhone 사용자 ${value.userId}에 계속 연결합니다.`:'계정은 연결했지만 최신 데이터를 불러오지 못했습니다. 새로고침해 주세요.')}catch(error){setToast(error instanceof ApiRequestError&&error.status===404?'iPhone의 최신 연결 코드를 확인해 주세요.':error instanceof ApiRequestError&&error.status===409?'이미 다른 아이디에 연결된 iPhone입니다.':'기기 연결에 실패했습니다. 잠시 후 다시 시도해 주세요.');throw error}}
 async function login(accountId:string){const value=await loginWebSession(accountId);setAccount(value);hydrateAccount(value);setLoginMessage('');setLoginRequired(false);await loadData()}
 async function logout(){
  window.speechSynthesis?.cancel();recognition.current?.stop();
  const revocation=logoutWebSession();
  if(account)clearCachedState(account.userId);
  setAccount(null);setDashboard(null);setReport(null);setPersonalization(null);setMemories([]);setDevices([]);setChats([]);setPhase('idle');setLoginRequired(true);
  setLoginMessage('로그아웃되었습니다.');
  await revocation;
 }

 const phaseText={idle:'무엇이든 이야기해 주세요',listening:'듣고 있어요',thinking:'당신의 흐름을 살펴보고 있어요',speaking:'답변하고 있어요'}[phase];
 const navItems:[ViewKey,string,typeof Command][]=[['today','오늘',Command],['timeline','타임라인',History],['report','주간 리포트',BarChart3],['data','데이터',Archive],['settings','설정',Settings2]];

 if(loginRequired)return <WebLoginView onLogin={login} message={loginMessage}/>;
 return <div className={`app-shell phase-${phase}`}>
  <div className="atmosphere"/><div className="grid-floor"/>
  <aside className="rail" aria-label="주요 메뉴"><button className="mark" onClick={()=>setView('today')} aria-label="Morrow 홈">M</button><nav>{navItems.map(([key,label,Icon])=><button key={key} className={view===key?'on':''} onClick={()=>setView(key)} aria-label={label} title={label}><Icon/></button>)}</nav></aside>
  <header className="topbar"><div className="identity"><i className="status-dot"/><div><b>MORROW</b><span>PERSONAL WELLNESS INTELLIGENCE</span></div></div><div className="system-status"><span className={`mode ${mode}`}><Signal/> {mode==='live'?'LIVE API':'OFFLINE · LAST SYNC'}</span><span><BrainCircuit/> {aiMode==='LIVE'?'AI LIVE':personalization?.personalized?`MEMORY ${personalization.evidenceCount}`:'AI READY'}</span><span><ShieldCheck/> PRIVATE BY DESIGN</span>{(account?.userId==='hackathon-demo'||account?.userId.startsWith('demo-'))&&<button className="demo-button" onClick={()=>setDemoOpen(true)}><Sparkles/> DEMO</button>}<button onClick={newSession}><Plus/> NEW SESSION</button></div></header>
  <main className="main-area">
   {dashboard&&view==='today'&&<TodayView dashboard={dashboard} phase={phase} phaseText={phaseText} particles={particles} chats={chats} message={message} sound={sound} feedbackDone={feedbackDone} refreshing={refreshing} onMessage={setMessage} onSend={send} onMic={toggleMic} onSound={()=>{setSound(value=>!value);window.speechSynthesis?.cancel()}} onSuggestion={send} onCheckIn={()=>setCheckInOpen(true)} onRecovery={()=>setRecoveryOpen(true)} onFeedback={feedback} onRefresh={()=>void loadData(true)}/>}
   {dashboard&&view==='timeline'&&<TimelineView items={dashboard.timeline} onCheckIn={()=>setCheckInOpen(true)}/>}
   {report&&view==='report'&&<ReportView report={report}/>}
   {view==='data'&&<DataView mode={mode} profile={personalization} memories={memories} onRebuild={()=>void rebuildLearning()} onAdd={addMemory} onExport={()=>void downloadData()} onForget={()=>void forgetConversation()} onDelete={()=>void deleteData()}/>}
   {view==='settings'&&<SettingsView account={account} devices={devices} aiHealthConsent={aiHealthConsent} onAIHealthConsent={value=>void changeAIHealthConsent(value)} onPair={pairAccount} onRevoke={id=>void revokeDevice(id)} onDeleteAccount={()=>void deleteAccount()} onLogout={()=>void logout()}/>}
   {!dashboard&&view!=='data'&&view!=='settings'&&<LoadingView error={loadError} onRetry={()=>void loadData(true)}/>}
  </main>
  <footer><span>WELLNESS SUPPORT — NOT MEDICAL DIAGNOSIS</span><span className="session"><i/> {mode==='live'?'API CONNECTED':'LAST SAVED DATA'}</span></footer>
  {checkInOpen&&<CheckInModal userId={account?.userId??'pending-user'} onClose={()=>setCheckInOpen(false)} onSave={saveCheckIn}/>}
  {recoveryOpen&&dashboard&&<RecoveryModal action={actionForRecommendation(dashboard.recommendation?.title)} reason={dashboard.recommendation?.rationale??dashboard.scoreReasons?.[0]??'최근 개인 기준에서 회복 행동이 필요해 보여요.'} confidence={dashboard.scoreConfidence} onClose={()=>setRecoveryOpen(false)} onComplete={outcome=>{setRecoveryOpen(false);void feedback(outcome==='IMPROVED')}}/>}
  {demoOpen&&<DemoScenarioModal onClose={()=>setDemoOpen(false)} onApply={loadDemoScenario}/>}
  {toast&&<div className="toast" role="status"><Check/>{toast}</div>}
 </div>
}

type TodayProps={dashboard:Dashboard;phase:Phase;phaseText:string;particles:{left:string;top:string;delay:string;size:number}[];chats:Chat[];message:string;sound:boolean;feedbackDone:boolean;refreshing:boolean;onMessage:(value:string)=>void;onSend:(value?:string)=>void;onMic:()=>void;onSound:()=>void;onSuggestion:(value:string)=>void;onCheckIn:()=>void;onRecovery:()=>void;onFeedback:(helpful:boolean)=>void;onRefresh:()=>void};

function TodayView({dashboard,phase,phaseText,particles,chats,message,sound,feedbackDone,refreshing,onMessage,onSend,onMic,onSound,onSuggestion,onCheckIn,onRecovery,onFeedback,onRefresh}:TodayProps){
 const sleepHours=Math.floor(dashboard.metrics.sleepMinutes/60);const sleepMinutes=dashboard.metrics.sleepMinutes%60;
 const conversationRef=useRef<HTMLDivElement>(null);
 useEffect(()=>{const node=conversationRef.current;if(node)node.scrollTo({top:node.scrollHeight,behavior:phase==='speaking'?'auto':'smooth'})},[chats,phase]);
 return <div className="today-grid">
  <section className="assistant-panel">
   <div className="panel-kicker"><BrainCircuit/> ADAPTIVE COMPANION <button className={refreshing?'rotating':''} onClick={onRefresh} aria-label="데이터 새로고침"><RefreshCw/></button></div>
   <div className="phase-label"><i/>{phaseText}</div>
   <div className="ai-core" aria-label={phaseText}><div className="outer-orbit"><i/><i/><i/></div><div className="tech-ring ring-one"/><div className="tech-ring ring-two"/><div className="scan-line"/><div className="core-halo"/><div className="core-surface"><div className="wave">{Array.from({length:25},(_,index)=><i key={index} style={{height:`${12+Math.abs(12-index)*1.2+(index%4)*4}px`,animationDelay:`-${index*.06}s`}}/>)}</div><div className="thinking-dots"><i/><i/><i/></div></div>{particles.map((particle,index)=><i className="particle" key={index} style={{left:particle.left,top:particle.top,width:particle.size,height:particle.size,animationDelay:particle.delay}}/>)}</div>
   <div className="conversation" ref={conversationRef} aria-live="polite">{chats.map(item=><p key={item.id} className={item.role}>{item.text}{item.role==='ai'&&phase==='speaking'&&item.id===chats.at(-1)?.id?<i className="cursor"/>:null}</p>)}</div>
   <div className="suggestions">{phase==='idle'&&suggestions.map(value=><button key={value} onClick={()=>onSuggestion(value)}>{value}<ChevronRight/></button>)}</div>
   <form className="composer" onSubmit={(event:FormEvent)=>{event.preventDefault();onSend()}}><button aria-label={phase==='listening'?'음성 듣기 중지':'음성으로 말하기'} type="button" className={`mic ${phase==='listening'?'active':''}`} onClick={onMic}>{phase==='listening'?<MicOff/>:<Mic/>}</button><div><input value={message} onChange={event=>onMessage(event.target.value)} placeholder={phase==='listening'?'듣고 있어요...':'Morrow에게 이야기하세요'} disabled={phase==='thinking'||phase==='speaking'}/><span>{phase==='thinking'?'최근 흐름과 대화를 연결하는 중':'Enter로 보내기 · 대화는 웰니스 범위에서 답합니다'}</span></div><button aria-label={sound?'음성 답변 끄기':'음성 답변 켜기'} className="sound" type="button" onClick={onSound}>{sound?<Volume2/>:<VolumeX/>}</button><button aria-label="메시지 보내기" className="send" type="submit"><Send/></button></form>
  </section>
  <aside className="insights-panel">
   <div className="insight-heading"><div><span>TODAY · PERSONAL BASELINE</span><h1>오늘의 회복 신호</h1></div><button onClick={onCheckIn}><Plus/> 체크인</button></div>
   <div className="score-card"><div className="score-ring" style={{'--score':`${dashboard.score*3.6}deg`} as React.CSSProperties}><div><b>{dashboard.score>0?dashboard.score:'—'}</b><span>회복 여유</span></div></div><div className="score-copy"><span className="load-badge">{dashboard.score===0?'데이터 대기':dashboard.wellnessLoad==='NORMAL'?'안정적':dashboard.wellnessLoad==='MODERATE'?'조금 높음':'평소보다 높음'}</span><h2>{dashboard.score===0?<>HealthKit 데이터를<br/>연결해 주세요.</>:<>무리하기보다<br/>리듬을 되찾아 보세요.</>}</h2><p>{dashboard.scoreReasons?.[0]??'최근 기록이 쌓이면 개인 기준선과 비교해 드려요.'}</p></div></div>
   <div className="metric-grid"><Metric icon={<MoonStar/>} label="수면" value={dashboard.metrics.sleepMinutes>0?`${sleepHours}h ${sleepMinutes}m`:'—'} trend="HealthKit 파생 요약"/><Metric icon={<HeartPulse/>} label="안정 심박" value={dashboard.metrics.restingHeartRate>0?`${dashboard.metrics.restingHeartRate} bpm`:'—'} trend="최근 동기화 값"/><Metric icon={<Activity/>} label="HRV" value={dashboard.metrics.hrv>0?`${dashboard.metrics.hrv} ms`:'—'} trend="최근 동기화 값"/><Metric icon={<Footprints/>} label="걸음" value={dashboard.metrics.steps>0?dashboard.metrics.steps.toLocaleString('ko-KR'):'—'} trend="iPhone · Watch 연동"/><Metric icon={<Activity/>} label="활동 에너지" value={dashboard.metrics.activeEnergyKcal>0?`${dashboard.metrics.activeEnergyKcal} kcal`:'—'} trend="오늘 누적"/><Metric icon={<Watch/>} label="운동" value={dashboard.metrics.exerciseMinutes>0?`${dashboard.metrics.exerciseMinutes}분`:'—'} trend="오늘 누적"/></div>
   {dashboard.recommendation?<div className="recommendation"><div className="recommend-top"><span><Sparkles/> NEXT BEST ACTION</span><small>실행 후 효과 학습</small></div><h2>{dashboard.recommendation.title}</h2><p>{dashboard.recommendation.rationale}</p>{feedbackDone?<div className="feedback-complete"><Check/> 실행 효과를 다음 추천에 반영했어요</div>:<div className="recommend-actions"><button className="primary" onClick={onRecovery}><Sparkles/> 지금 바로 실행</button><button onClick={()=>onFeedback(false)} aria-label="다른 행동 추천"><ThumbsDown/></button></div>}</div>:<button className="empty-recommendation" onClick={onCheckIn}><Plus/> 지금 상태를 기록하면 맞춤 행동을 제안해요</button>}
  </aside>
  <section className="timeline-strip"><div className="strip-head"><span>TODAY'S SIGNAL STORY</span><b>{dashboard.timeline.length}개의 의미 있는 변화</b></div><div className="timeline-cards">{dashboard.timeline.slice(-3).map(item=><TimelineCard key={item.id} item={item}/>)}</div></section>
 </div>
}

function Metric({icon,label,value,trend}:{icon:React.ReactNode;label:string;value:string;trend:string}){return <div className="metric"><span>{icon}{label}</span><b>{value}</b><small>{trend}</small></div>}

function TimelineCard({item}:{item:TimelineItem}){const icon:Record<TimelineKind,React.ReactNode>={sleep:<MoonStar/>,checkin:<Watch/>,recovery:<Sparkles/>,activity:<Footprints/>,insight:<BrainCircuit/>};return <article className={`timeline-card ${item.kind}`}><div className="timeline-icon">{icon[item.kind]}</div><div><span>{item.time} {item.userConfirmed&&<i>확인됨</i>}</span><b>{item.title}</b><p>{item.detail}</p></div></article>}

function TimelineView({items,onCheckIn}:{items:TimelineItem[];onCheckIn:()=>void}){return <div className="page-view"><div className="page-heading"><div><span>SIGNAL STORY</span><h1>오늘의 타임라인</h1><p>기기 데이터와 직접 입력을 섞지 않고, 근거와 확인 상태를 함께 보여줘요.</p></div><button className="page-action" onClick={onCheckIn}><Plus/> 새 체크인</button></div>{items.length?<div className="timeline-list">{items.map((item,index)=><div className="timeline-row" key={item.id}><div className="timeline-axis"><span>{item.time}</span><i/>{index<items.length-1&&<b/>}</div><TimelineCard item={item}/></div>)}</div>:<div className="empty-state"><History/><h2>아직 오늘의 기록이 없어요</h2><p>30초 체크인으로 첫 신호를 남겨보세요.</p><button onClick={onCheckIn}>상태 기록하기</button></div>}</div>}

function ReportView({report}:{report:WeeklyReport}){
 const points=report.dailyScores??[];
 return <div className="page-view report-view"><div className="page-heading"><div><span>WEEKLY PATTERN REPORT</span><h1>이번 주, 무엇이 실제로 도움이 됐을까요?</h1><p>상태 변화뿐 아니라 실행한 회복 행동과 직접 남긴 효과를 함께 보여줘요.</p></div><div className="week-chip">{weekRange()}</div></div><div className="report-grid"><section className="report-hero"><div><span>WELLNESS MOMENTUM</span><b>{report.totalCheckIns?Math.round(report.improvementRate):'—'}</b><small>{report.totalCheckIns?`지난주 대비 ${report.changeFromPrevious>=0?'+':''}${Math.round(report.changeFromPrevious)}점`:'체크인이 필요해요'}</small></div><div className="weekly-chart">{points.map((point,index)=><div key={point.date}><i style={{height:`${point.score??2}%`}} className={point.score!==null&&point.score===Math.max(...points.map(value=>value.score??0))?'peak':''}/><span>{['일','월','화','수','목','금','토'][new Date(`${point.date}T00:00:00`).getDay()]}</span></div>)}</div></section><section className="report-summary"><span>이번 주 요약</span><h2>{report.insights}</h2><div><small>체크인</small><b>{report.totalCheckIns}회</b></div><div><small>가장 잦은 상태</small><b>{statusLabel[report.topStatus??'']??'기록 없음'}</b></div><div><small>주요 맥락</small><b>{causeLabel[report.topCause??'']??'기록 없음'}</b></div></section><section className="recovery-effect"><div><span>RECOVERY EFFECT LOOP</span><h2>{report.topHelpfulAction??'효과를 학습하는 중'}</h2><p>{report.recoveryInsight}</p></div><div className="effect-metrics"><div><small>제안</small><b>{report.suggestedRecoveryCount}회</b></div><div><small>완료</small><b>{report.completedRecoveryCount}회</b></div><div><small>나아짐</small><b>{Math.round(report.recoveryHelpfulRate)}%</b></div></div></section><section className="patterns"><span>PATTERN INTELLIGENCE</span>{report.patterns.map((pattern,index)=><article key={pattern}><i>0{index+1}</i><p>{translatePattern(pattern)}</p></article>)}</section><section className="trust-card"><ShieldCheck/><div><b>이 인사이트를 믿을 수 있는 이유</b><p>실제 일별 체크인과 회복 행동 뒤 직접 남긴 효과만 비교했어요. 의료적 판단이나 다른 사용자와의 비교는 하지 않습니다.</p></div></section></div></div>
}

function DemoScenarioModal({onClose,onApply}:{onClose:()=>void;onApply:(scenario:DemoScenario)=>Promise<void>}){
 const[loading,setLoading]=useState<DemoScenario|null>(null);
 const scenarios:{key:DemoScenario;title:string;description:string}[]=[
  {key:'SHORT_SLEEP',title:'짧은 수면 뒤 오전 피로',description:'수면 감소 → 피로 체크인 → 물과 짧은 걷기 → 효과 학습'},
  {key:'SEDENTARY',title:'오래 앉은 오후의 집중 저하',description:'낮은 활동량 → 집중 저하 → 스트레칭 → 효과 학습'},
  {key:'TENSION',title:'발표 전 긴장 상승',description:'긴장 신호 → 근거 설명 → 1분 호흡 → 효과 학습'}
 ];
 async function choose(value:DemoScenario){setLoading(value);await onApply(value);setLoading(null)}
 return <div className="modal-backdrop"><div className="demo-modal" role="dialog" aria-modal="true" aria-label="데모 시나리오 선택"><button className="modal-close" onClick={onClose} aria-label="닫기"><X/></button><span>AAC JUDGING SCENARIOS</span><h2>감지부터 효과 학습까지<br/>한 흐름으로 확인하세요</h2><p>선택한 시나리오의 합성 데이터로 데모 계정만 초기화됩니다.</p><div>{scenarios.map(item=><button key={item.key} onClick={()=>void choose(item.key)} disabled={loading!==null}><i><Sparkles/></i><span><b>{item.title}</b><small>{item.description}</small></span>{loading===item.key?<RefreshCw className="rotating"/>:<ChevronRight/>}</button>)}</div><small><ShieldCheck/> 실제 사용자 기록에는 영향을 주지 않습니다.</small></div></div>
}

function DataView({mode,profile,memories,onRebuild,onAdd,onExport,onForget,onDelete}:{mode:ConnectionMode;profile:PersonalizationProfile|null;memories:UserMemory[];onRebuild:()=>void;onAdd:(type:'PREFERENCE'|'GOAL',summary:string)=>Promise<void>;onExport:()=>void;onForget:()=>void;onDelete:()=>void}){
 const[memoryText,setMemoryText]=useState('');const[memoryType,setMemoryType]=useState<'PREFERENCE'|'GOAL'>('PREFERENCE');const[saving,setSaving]=useState(false);
 async function submitMemory(event:FormEvent){event.preventDefault();const clean=memoryText.trim();if(!clean)return;setSaving(true);await onAdd(memoryType,clean);setMemoryText('');setSaving(false)}
 const memoryLabel:Record<UserMemory['type'],string>={TRIGGER_PATTERN:'반복 맥락',RECOVERY_STRATEGY:'회복 피드백',PREFERENCE:'선호',GOAL:'목표'};
 return <div className="page-view privacy-view"><div className="page-heading"><div><span>MY DATA & PERSONAL MEMORY</span><h1>내 기록과 AI 기억을 관리하세요</h1><p>쌓인 기록, 개인화 근거, 데이터 보관 범위를 한 화면에서 확인하고 관리할 수 있어요.</p></div><button className="page-action" onClick={onRebuild}><RefreshCw/> 기록에서 다시 학습</button></div>
  <section className="learning-console">
   <div className="learning-score"><BrainCircuit/><div><span>PERSONALIZATION ENGINE</span><b>{profile?.personalized?'개인화 활성':'학습 대기'}</b><p>활성 메모리 {profile?.activeMemoryCount??0}개 · 누적 근거 {profile?.evidenceCount??0}건 · 도움 된 전략 {profile?.helpfulStrategyCount??0}개</p></div></div>
   <div className="routine-presets"><span>회복이 자주 필요한 순간</span>{['수면이 부족한 아침','업무·학업 중 집중이 흐려질 때','오래 앉아 움직임이 적을 때','발표·회의 전 긴장될 때'].map(value=><button key={value} onClick={()=>void onAdd('GOAL',value)}>{value}</button>)}</div>
   <form className="memory-form" onSubmit={submitMemory}><div><button type="button" className={memoryType==='PREFERENCE'?'on':''} onClick={()=>setMemoryType('PREFERENCE')}>내 선호</button><button type="button" className={memoryType==='GOAL'?'on':''} onClick={()=>setMemoryType('GOAL')}>내 목표</button></div><input maxLength={600} value={memoryText} onChange={event=>setMemoryText(event.target.value)} placeholder="예: 강한 운동보다 짧은 산책을 선호해요"/><button disabled={saving||!memoryText.trim()}><Plus/> 기억하기</button></form>
   <div className="memory-list">{memories.length?memories.slice(0,8).map(memory=><article key={memory.id}><span>{memoryLabel[memory.type]}</span><p>{memory.summary}</p><small>신뢰도 {Math.round(memory.confidence*100)}% · 근거 {memory.evidenceCount}건</small></article>):<div className="memory-empty">체크인과 추천 피드백이 쌓이면 여기에 개인화 근거가 표시됩니다.</div>}</div>
  </section>
  <div className="privacy-grid"><article><div className="privacy-icon"><HeartPulse/></div><span>HEALTHKIT</span><h2>원본은 기기에,<br/>파생 요약만 동기화</h2><p>허용한 건강 원본 샘플은 iPhone과 Watch에서만 읽고, 사용자가 켠 경우 화면용 일별 요약만 서버로 동기화해요.</p></article><article><div className="privacy-icon"><LockKeyhole/></div><span>ACCOUNT MEMORY</span><h2>서버에는 설명 가능한<br/>개인 메모리만</h2><p>체크인과 피드백에서 만들어진 패턴은 근거 수와 신뢰도를 함께 저장하고 AI 요청 때만 사용해요.</p></article><article><div className="privacy-icon"><ShieldCheck/></div><span>USER CONTROL</span><h2>언제든 기록과 기억을<br/>함께 삭제</h2><p>전체 삭제 시 체크인, 파생 건강 요약, 대화, 추천 피드백, 개인화 메모리까지 모두 제거해요.</p></article></div>
  <div className="data-status"><div><i className={mode}/><span>현재 연결</span><b>{mode==='live'?'운영 API · PostgreSQL 영구 저장':'오프라인 · 마지막 동기화 데이터'}</b></div><div><span>AI 사용 범위</span><b>계정별 개인화 · 범용 학습 제외</b></div><button onClick={onExport}><Archive/> 내 데이터 내려받기</button><button onClick={onForget}><BrainCircuit/> 대화 기억만 삭제</button><button onClick={onDelete}><Trash2/> 모든 기록과 AI 메모리 삭제</button></div><div className="safety-note"><BrainCircuit/><p><b>Morrow는 의료기기나 응급 서비스가 아닙니다.</b> 증상이 지속되거나 긴급한 도움이 필요하면 의료 전문가 또는 지역 응급기관에 연락하세요.</p></div></div>
}

function SettingsView({account,devices,aiHealthConsent,onAIHealthConsent,onPair,onRevoke,onDeleteAccount,onLogout}:{account:WebSession|null;devices:ConnectedDevice[];aiHealthConsent:boolean;onAIHealthConsent:(value:boolean)=>void;onPair:(code:string)=>Promise<void>;onRevoke:(id:string)=>void;onDeleteAccount:()=>void;onLogout:()=>void}){
 const[pairCode,setPairCode]=useState('');const[pairing,setPairing]=useState(false);const[pairError,setPairError]=useState('');
 async function submitPair(event:FormEvent){event.preventDefault();const clean=pairCode.trim();if(!clean)return;setPairing(true);setPairError('');try{await onPair(clean);setPairCode('')}catch(error){setPairError(error instanceof ApiRequestError&&error.status===404?'코드가 만료됐거나 일치하지 않습니다. iPhone 설정의 최신 코드를 입력해 주세요.':error instanceof ApiRequestError&&error.status===409?'이 iPhone은 다른 아이디에 이미 연결되어 있습니다.':'연결하지 못했습니다. 네트워크 상태를 확인해 주세요.')}finally{setPairing(false)}}
 return <div className="page-view settings-view"><div className="page-heading"><div><span>ACCOUNT & CONNECTIONS</span><h1>계정과 연결을 설정하세요</h1><p>iPhone 연결, 로그인된 기기, AI 건강정보 사용 여부를 여기에서 관리해요.</p></div></div>
  <section className="device-pairing"><div><Watch/><span>IPHONE CONNECTION</span><b>{account?`사용자 ${account.userId}`:'서버 연결 대기'}</b><p>iPhone 설정의 코드를 한 번 입력하면 이 아이디에 연결되고, 다음 로그인부터는 다시 입력하지 않아도 됩니다.</p></div><form onSubmit={submitPair}><input aria-label="iPhone 연결 코드" maxLength={8} value={pairCode} onChange={event=>setPairCode(event.target.value.toUpperCase().replace(/[^2-9A-HJ-NP-Z-]/g,''))} placeholder="6자리 연결 코드"/><button disabled={pairing||!pairCode.trim()}>{pairing?<RefreshCw className="rotating"/>:<Signal/>} {pairing?'연결 확인 중':'iPhone 연결'}</button>{pairError?<small className="pair-error">{pairError}</small>:<small>현재 웹 기기 코드: {account?.pairingCode??'—'}</small>}</form></section>
  <section className="connected-devices"><span>CONNECTED DEVICES</span>{devices.length?devices.map(device=><article key={device.id}><div><b>{device.deviceName}</b><small>{device.platform} · {new Date(device.lastSeenAt).toLocaleString('ko-KR')}</small></div>{device.deviceId!==account?.deviceId&&<button onClick={()=>onRevoke(device.id)}>연결 해제</button>}</article>):<p className="devices-empty">연결된 기기를 불러오는 중이거나 아직 다른 기기가 없습니다.</p>}</section>
  <section className="ai-consent"><div><BrainCircuit/><span><b>AI 답변에 건강 요약 사용</b><small>직접 허용한 경우에만 파생 건강 요약을 AI 답변에 사용합니다.</small></span></div><button className={aiHealthConsent?'on':''} onClick={()=>onAIHealthConsent(!aiHealthConsent)}>{aiHealthConsent?'허용됨':'허용 안 함'}</button></section>
  <section className="settings-account"><div><LockKeyhole/><span><small>로그인 계정</small><b>{account?.userId??'연결되지 않음'}</b></span></div><div><button className="logout-button" onClick={onLogout}><LogOut/> 로그아웃</button><button className="danger-button" onClick={onDeleteAccount}><Trash2/> 계정 완전 삭제</button></div></section>
 </div>
}

function actionForRecommendation(title?:string):RecoveryAction{
 const value=title??'';
 if(value.includes('걷')||value.includes('산책'))return'WALK';
 if(value.includes('물'))return'WATER_WALK';
 if(value.includes('스트레칭')||value.includes('어깨'))return'STRETCH';
 if(value.includes('집중')||value.includes('할 일'))return'FOCUS';
 if(value.includes('화면')||value.includes('눈'))return'SCREEN_BREAK';
 return'BREATH';
}

function RecoveryModal({action,reason,confidence,onClose,onComplete}:{action:RecoveryAction;reason:string;confidence:string;onClose:()=>void;onComplete:(outcome:'IMPROVED'|'SAME'|'WORSE')=>void}){
 const[remaining,setRemaining]=useState(60);const[running,setRunning]=useState(false);const[attemptId,setAttemptId]=useState('');const[submitting,setSubmitting]=useState(false);
 const labels:Record<RecoveryAction,[string,string]>={BREATH:['1분 호흡','4초 들이쉬고 6초 내쉬어 보세요.'],WALK:['1분 가볍게 걷기','자리에서 일어나 편한 속도로 움직여 보세요.'],WATER_WALK:['물 한 잔과 걷기','물을 마시고 잠시 천천히 걸어보세요.'],STRETCH:['1분 스트레칭','목과 어깨부터 천천히 풀어보세요.'],FOCUS:['1분 집중 시작','방해 요소를 닫고 한 가지만 시작해 보세요.'],SCREEN_BREAK:['1분 화면 휴식','먼 곳을 바라보고 어깨 힘을 빼보세요.']};
 useEffect(()=>{let active=true;void createRecoveryAttempt(action,reason,confidence).then(value=>{if(active)setAttemptId(value.id)}).catch(()=>{});return()=>{active=false}},[action,reason,confidence]);
 useEffect(()=>{if(!running||remaining<=0)return;const timer=window.setInterval(()=>setRemaining(value=>{if(value<=1){window.clearInterval(timer);setRunning(false);return 0}return value-1}),1000);return()=>window.clearInterval(timer)},[running,remaining]);
 async function finish(outcome:'IMPROVED'|'SAME'|'WORSE'){if(submitting)return;setSubmitting(true);try{if(attemptId)await completeRecoveryAttempt(attemptId,outcome)}finally{onComplete(outcome)}}
 return <div className="modal-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)onClose()}}><section className="recovery-modal"><button className="modal-close" onClick={onClose} aria-label="닫기"><X/></button><span>WHY NOW · {confidence}</span><p className="recovery-reason">{reason}</p><div className="recovery-timer" style={{'--progress':`${(60-remaining)*6}deg`} as React.CSSProperties}><div><b>{remaining}</b><small>{running?'회복 중':labels[action][0]}</small></div></div>{remaining>0?<><h2>{labels[action][0]}</h2><p>{labels[action][1]}</p><button className="recovery-start" onClick={()=>setRunning(value=>!value)}>{running?'잠시 멈춤':'지금 시작'}</button></>:<><h2>실행 전보다 조금 나아졌나요?</h2><div className="recovery-outcomes"><button disabled={submitting} onClick={()=>void finish('IMPROVED')}>나아졌어요</button><button disabled={submitting} onClick={()=>void finish('SAME')}>그대로예요</button><button disabled={submitting} onClick={()=>void finish('WORSE')}>더 불편해요</button></div></>}</section></div>
}

function CheckInModal({userId,onClose,onSave}:{userId:string;onClose:()=>void;onSave:(input:CheckInInput)=>Promise<void>}){
 const[status,setStatus]=useState<CheckInStatus>('TIRED');const[cause,setCause]=useState<CheckInCause>('SLEEP');const[note,setNote]=useState('');const[saving,setSaving]=useState(false);
 async function submit(event:FormEvent){event.preventDefault();setSaving(true);await onSave({userId,status,cause,note:note.trim(),source:'WEB',recordedAt:new Date().toISOString()});setSaving(false)}
 return <div className="modal-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)onClose()}}><form className="checkin-modal" onSubmit={submit}><div className="modal-head"><div><span>30-SECOND CHECK-IN</span><h2>지금 어떤 상태인가요?</h2></div><button type="button" onClick={onClose} aria-label="닫기"><X/></button></div><div className="status-options">{statusOptions.map(([value,label,description])=><button type="button" key={value} className={status===value?'selected':''} onClick={()=>setStatus(value)}><i>{status===value&&<Check/>}</i><b>{label}</b><span>{description}</span></button>)}</div><label className="field"><span>무엇과 가장 관련 있나요?</span><div className="cause-options">{causeOptions.map(([value,label])=><button type="button" key={value} className={cause===value?'selected':''} onClick={()=>setCause(value)}>{label}</button>)}</div></label><label className="field"><span>필요하면 맥락을 남겨주세요 <small>선택</small></span><textarea maxLength={500} value={note} onChange={event=>setNote(event.target.value)} placeholder="예: 어제 마감 때문에 늦게 잠들었어요"/><small>{note.length}/500</small></label><button className="save-checkin" disabled={saving}>{saving?<><RefreshCw className="rotating"/> 흐름에 반영 중</>:<><Check/> 체크인 저장</>}</button><p className="modal-foot"><LockKeyhole/> 직접 입력은 생체 신호보다 우선하며 언제든 삭제할 수 있어요.</p></form></div>
}

function LoadingView({error,onRetry}:{error:string;onRetry:()=>void}){return <div className="loading-view"><div className={error?'loading-orb stopped':'loading-orb'}/><span>{error||'개인 기준선을 연결하고 있어요'}</span>{error&&<button onClick={onRetry}><RefreshCw/> 다시 불러오기</button>}</div>}

function WebLoginView({onLogin,message}:{onLogin:(accountId:string)=>Promise<void>;message:string}){
 const[accountId,setAccountId]=useState('');const[loading,setLoading]=useState(false);const[error,setError]=useState('');
 async function submit(event:FormEvent){event.preventDefault();const clean=accountId.trim();if(!clean)return;setLoading(true);setError('');try{await onLogin(clean)}catch{setError('아이디를 확인하거나 잠시 후 다시 시도해 주세요.')}finally{setLoading(false)}}
 return <main className="login-shell"><div className="login-glow"/><section className="login-card"><div className="login-brand"><i>M</i><div><b>MORROW</b><span>ACCOUNT LOGIN</span></div></div><div className="login-copy"><span>ONE ACCOUNT · ALL DEVICES</span><h1>아이디로<br/>다시 연결하세요</h1><p>처음에는 아이디만 입력합니다. iPhone 연결 코드는 로그인 후 설정에서 한 번만 연결하세요.</p></div>{message&&<p className="login-notice">{message}</p>}<form onSubmit={submit}><label><span>아이디</span><input autoFocus autoComplete="username" maxLength={80} value={accountId} onChange={event=>setAccountId(event.target.value)} placeholder="아이디 입력"/></label>{error&&<p className="login-error">{error}</p>}<button disabled={loading||!accountId.trim()}>{loading?<RefreshCw className="rotating"/>:<LockKeyhole/>}{loading?'계정 확인 중':'아이디로 로그인'}</button></form><footer><ShieldCheck/> 한 번 연결한 iPhone 계정은 다시 로그인해도 유지됩니다.</footer></section></main>
}

function translatePattern(value:string){return value.replaceAll('LOW_FOCUS','집중 저하').replaceAll('TIRED','피로').replaceAll('TENSE','긴장').replaceAll('OK','괜찮음').replaceAll('SLEEP','수면').replaceAll('WORK','업무').replaceAll('STUDY','학업')}

function weekRange(){
 const today=new Date();const monday=new Date(today);monday.setHours(0,0,0,0);monday.setDate(today.getDate()-((today.getDay()+6)%7));const sunday=new Date(monday);sunday.setDate(monday.getDate()+6);
 return`${monday.getMonth()+1}월 ${monday.getDate()}일 — ${sunday.getMonth()+1}월 ${sunday.getDate()}일`;
}
