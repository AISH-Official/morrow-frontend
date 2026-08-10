import{FormEvent,useEffect,useMemo,useRef,useState}from'react';
import{Activity,Archive,BarChart3,BrainCircuit,Check,ChevronRight,Command,Footprints,HeartPulse,History,LockKeyhole,Mic,MicOff,MoonStar,Plus,RefreshCw,Send,Settings2,ShieldCheck,Signal,Sparkles,ThumbsDown,ThumbsUp,Trash2,Volume2,VolumeX,Watch,X}from'lucide-react';
import{addPersonalMemory,appendLocalCheckIn,clearWellnessData,createCheckIn,getDashboard,getPersonalization,getStoredWebSession,getWeeklyReport,getWebSession,loginWebSession,pairWebSession,rebuildPersonalization,sendAssistantMessage,submitRecommendationFeedback}from'./api';
import type{WebSession}from'./api';
import type{CheckInCause,CheckInInput,CheckInStatus,ConnectionMode,Dashboard,PersonalizationProfile,TimelineItem,TimelineKind,UserMemory,WeeklyReport}from'./types';

type Role='ai'|'user';
type Phase='idle'|'listening'|'thinking'|'speaking';
type ViewKey='today'|'timeline'|'report'|'privacy';
type Chat={id:number;role:Role;text:string};
type RecognitionEvent={results:ArrayLike<{0:{transcript:string};isFinal:boolean}>};
type RecognitionLike={lang:string;continuous:boolean;interimResults:boolean;start:()=>void;stop:()=>void;onresult:((event:RecognitionEvent)=>void)|null;onend:(()=>void)|null;onerror:(()=>void)|null};

const suggestions=['오늘 컨디션 어때?','잠을 잘 못 잤어','집중할 수 있게 도와줘'];
const statusOptions:[CheckInStatus,string,string][]=[['OK','괜찮아요','안정적인 상태'],['TIRED','피곤해요','에너지가 부족함'],['TENSE','긴장돼요','몸과 마음이 굳음'],['LOW_FOCUS','집중이 안 돼요','생각이 흐릿함'],['UNCOMFORTABLE','불편해요','몸이 편하지 않음']];
const causeOptions:[CheckInCause,string][]=[['SLEEP','수면'],['WORK','업무'],['STUDY','학업'],['RELATIONSHIP','관계'],['PHYSICAL','신체'],['UNKNOWN','잘 모르겠어요']];
const statusLabel:Record<string,string>={OK:'괜찮음',TENSE:'긴장',TIRED:'피로',LOW_FOCUS:'집중 저하',UNCOMFORTABLE:'불편함'};
const causeLabel:Record<string,string>={SLEEP:'수면',WORK:'업무',STUDY:'학업',RELATIONSHIP:'관계',PHYSICAL:'신체',UNKNOWN:'복합 요인'};

export default function App(){
 const[dashboard,setDashboard]=useState<Dashboard|null>(null);
 const[report,setReport]=useState<WeeklyReport|null>(null);
 const[mode,setMode]=useState<ConnectionMode>('demo');
 const[view,setView]=useState<ViewKey>('today');
 const[message,setMessage]=useState('');
 const[phase,setPhase]=useState<Phase>('idle');
 const[sound,setSound]=useState(false);
 const[chats,setChats]=useState<Chat[]>([
  {id:1,role:'ai',text:'좋은 저녁이에요, 수빈님.'},
  {id:2,role:'ai',text:'오늘은 평소보다 조금 지쳐 보여요. 지금 어떤 상태인지 이야기해 주세요.'}
 ]);
 const[checkInOpen,setCheckInOpen]=useState(false);
 const[toast,setToast]=useState('');
 const[feedbackDone,setFeedbackDone]=useState(false);
 const[refreshing,setRefreshing]=useState(false);
 const[personalization,setPersonalization]=useState<PersonalizationProfile|null>(null);
 const[memories,setMemories]=useState<UserMemory[]>([]);
 const[aiMode,setAiMode]=useState<'LIVE'|'FALLBACK'|'LOCAL'|'UNKNOWN'>('UNKNOWN');
 const[account,setAccount]=useState<WebSession|null>(null);
 const[loginRequired,setLoginRequired]=useState(()=>getStoredWebSession()===null);
 const recognition=useRef<RecognitionLike|null>(null);
 const nextId=useRef(3);
 const particles=useMemo(()=>Array.from({length:34},(_,index)=>({left:`${(index*47)%100}%`,top:`${(index*71)%100}%`,delay:`-${(index%13)*.37}s`,size:1+(index%3)})),[]);

 useEffect(()=>{const stored=getStoredWebSession();if(stored){setAccount(stored);void loadData()}return()=>{recognition.current?.stop();window.speechSynthesis?.cancel()}},[]);
 useEffect(()=>{if(!toast)return;const timer=window.setTimeout(()=>setToast(''),2800);return()=>window.clearTimeout(timer)},[toast]);

 async function loadData(showSpinner=false){
  if(showSpinner)setRefreshing(true);
  const[dashResult,weekly,personal]=await Promise.all([getDashboard(),getWeeklyReport(),getPersonalization()]);
  setDashboard(dashResult.data);setMode(dashResult.mode);setReport(weekly);setPersonalization(personal.profile);setMemories(personal.memories);setRefreshing(false);
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
  const result=await sendAssistantMessage(clean);setAiMode(result.aiMode);if(result.personalized)setPersonalization(value=>value?{...value,evidenceCount:Math.max(value.evidenceCount,result.personalizationEvidenceCount),personalized:true}:value);streamAnswer(result.content);
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

 async function saveCheckIn(input:CheckInInput){
  const result=await createCheckIn(input);
  if(dashboard&&result.id.startsWith('local-'))setDashboard(appendLocalCheckIn(dashboard,input,result.id));
  else await loadData();
  setCheckInOpen(false);setFeedbackDone(false);setToast(mode==='live'?'체크인이 모든 기기 흐름에 반영됐어요.':'체크인을 데모 타임라인에 반영했어요.');
 }

 async function feedback(helpful:boolean){
  if(!dashboard?.recommendation)return;
  try{await submitRecommendationFeedback(dashboard.recommendation.id,helpful);const personal=await getPersonalization();setPersonalization(personal.profile);setMemories(personal.memories)}catch{setMode('demo')}
  setFeedbackDone(true);setToast(helpful?'좋아요. 이 회복 방법을 더 잘 기억할게요.':'알겠어요. 다음에는 다른 방법을 제안할게요.');
  const now=new Date();
  const recovery:TimelineItem={id:`feedback-${Date.now()}`,time:now.toLocaleTimeString('ko-KR',{hour:'2-digit',minute:'2-digit',hour12:false}),title:'회복 활동 피드백',detail:helpful?'짧은 걷기가 도움이 됐어요.':'이번 추천은 도움이 되지 않았어요.',kind:'recovery',userConfirmed:true};
  setDashboard(value=>value?{...value,timeline:[...value.timeline,recovery]}:value);
 }

 async function deleteData(){
  try{await clearWellnessData();await loadData();setToast('서버의 웰니스 기록과 개인화 메모리를 삭제했어요.')}catch{setDashboard(value=>value?{...value,timeline:[]}:value);setToast('이 데모 세션의 기록을 비웠어요.')}
 }

 async function rebuildLearning(){try{await rebuildPersonalization();const personal=await getPersonalization();setPersonalization(personal.profile);setMemories(personal.memories);setToast('전체 기록에서 개인화 메모리를 다시 학습했어요.')}catch{setToast('백엔드에 연결한 뒤 다시 시도해 주세요.')}}
 async function addMemory(type:'PREFERENCE'|'GOAL',summary:string){try{await addPersonalMemory(type,summary);const personal=await getPersonalization();setPersonalization(personal.profile);setMemories(personal.memories);setToast('직접 알려준 내용을 개인화 메모리에 저장했어요.')}catch{setToast('메모리를 저장하지 못했어요.')}}
 async function pairAccount(code:string){try{const value=await pairWebSession(code);setAccount(value);await loadData();setToast('iPhone·Watch와 같은 사용자 계정으로 연결됐어요.')}catch{setToast('연결 코드를 확인하고 다시 시도해 주세요.')}}
 async function login(username:string,password:string){const value=await loginWebSession(username,password);setAccount(value);setLoginRequired(false);await loadData()}

 const phaseText={idle:'무엇이든 이야기해 주세요',listening:'듣고 있어요',thinking:'당신의 흐름을 살펴보고 있어요',speaking:'답변하고 있어요'}[phase];
 const navItems:[ViewKey,string,typeof Command][]=[['today','오늘',Command],['timeline','타임라인',History],['report','주간 리포트',BarChart3],['privacy','데이터',Archive]];

 if(loginRequired)return <WebLoginView onLogin={login}/>;
 return <div className={`app-shell phase-${phase}`}>
  <div className="atmosphere"/><div className="grid-floor"/>
  <aside className="rail" aria-label="주요 메뉴"><button className="mark" onClick={()=>setView('today')} aria-label="Morrow 홈">M</button><nav>{navItems.map(([key,label,Icon])=><button key={key} className={view===key?'on':''} onClick={()=>setView(key)} aria-label={label} title={label}><Icon/></button>)}</nav><a className="device-link" href={`${import.meta.env.BASE_URL}device-preview/`} aria-label="기기 경험 보기" title="기기 경험"><Watch/></a><button className="settings" onClick={()=>setView('privacy')} aria-label="설정"><Settings2/></button></aside>
  <header className="topbar"><div className="identity"><i className="status-dot"/><div><b>MORROW</b><span>PERSONAL WELLNESS INTELLIGENCE</span></div></div><div className="system-status"><span className={`mode ${mode}`}><Signal/> {mode==='live'?'LIVE API':'DEMO SAFE MODE'}</span><span><BrainCircuit/> {aiMode==='LIVE'?'AI LIVE':personalization?.personalized?`MEMORY ${personalization.evidenceCount}`:'AI READY'}</span><span><ShieldCheck/> PRIVATE BY DESIGN</span><button onClick={newSession}><Plus/> NEW SESSION</button></div></header>
  <main className="main-area">
   {dashboard&&view==='today'&&<TodayView dashboard={dashboard} phase={phase} phaseText={phaseText} particles={particles} chats={chats} message={message} sound={sound} feedbackDone={feedbackDone} refreshing={refreshing} onMessage={setMessage} onSend={send} onMic={toggleMic} onSound={()=>{setSound(value=>!value);window.speechSynthesis?.cancel()}} onSuggestion={send} onCheckIn={()=>setCheckInOpen(true)} onFeedback={feedback} onRefresh={()=>void loadData(true)}/>}
   {dashboard&&view==='timeline'&&<TimelineView items={dashboard.timeline} onCheckIn={()=>setCheckInOpen(true)}/>}
   {report&&view==='report'&&<ReportView report={report}/>}
   {view==='privacy'&&<PrivacyView mode={mode} account={account} profile={personalization} memories={memories} onPair={pairAccount} onRebuild={()=>void rebuildLearning()} onAdd={addMemory} onDelete={()=>void deleteData()}/>}
   {!dashboard&&view!=='privacy'&&<LoadingView/>}
  </main>
  <footer><span>WELLNESS SUPPORT — NOT MEDICAL DIAGNOSIS</span><span className="session"><i/> {mode==='live'?'API CONNECTED':'RESILIENT DEMO SESSION'}</span></footer>
  {checkInOpen&&<CheckInModal userId={account?.userId??'pending-user'} onClose={()=>setCheckInOpen(false)} onSave={saveCheckIn}/>}
  {toast&&<div className="toast" role="status"><Check/>{toast}</div>}
 </div>
}

type TodayProps={dashboard:Dashboard;phase:Phase;phaseText:string;particles:{left:string;top:string;delay:string;size:number}[];chats:Chat[];message:string;sound:boolean;feedbackDone:boolean;refreshing:boolean;onMessage:(value:string)=>void;onSend:(value?:string)=>void;onMic:()=>void;onSound:()=>void;onSuggestion:(value:string)=>void;onCheckIn:()=>void;onFeedback:(helpful:boolean)=>void;onRefresh:()=>void};

function TodayView({dashboard,phase,phaseText,particles,chats,message,sound,feedbackDone,refreshing,onMessage,onSend,onMic,onSound,onSuggestion,onCheckIn,onFeedback,onRefresh}:TodayProps){
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
   <div className="score-card"><div className="score-ring" style={{'--score':`${dashboard.score*3.6}deg`} as React.CSSProperties}><div><b>{dashboard.score}</b><span>회복 여유</span></div></div><div className="score-copy"><span className="load-badge">{dashboard.wellnessLoad==='NORMAL'?'안정적':dashboard.wellnessLoad==='MODERATE'?'조금 높음':'평소보다 높음'}</span><h2>무리하기보다<br/>리듬을 되찾아 보세요.</h2><p>수면과 최근 체크인을 개인 기준선과 함께 살폈어요.</p></div></div>
   <div className="metric-grid"><Metric icon={<MoonStar/>} label="수면" value={`${sleepHours}h ${sleepMinutes}m`} trend="HealthKit 파생 요약"/><Metric icon={<HeartPulse/>} label="안정 심박" value={`${dashboard.metrics.restingHeartRate} bpm`} trend="최근 동기화 값"/><Metric icon={<Activity/>} label="HRV" value={`${dashboard.metrics.hrv} ms`} trend="최근 동기화 값"/><Metric icon={<Footprints/>} label="걸음" value={dashboard.metrics.steps.toLocaleString('ko-KR')} trend="iPhone · Watch 연동"/><Metric icon={<Activity/>} label="활동 에너지" value={`${dashboard.metrics.activeEnergyKcal} kcal`} trend="오늘 누적"/><Metric icon={<Watch/>} label="운동" value={`${dashboard.metrics.exerciseMinutes}분`} trend="오늘 누적"/></div>
   {dashboard.recommendation?<div className="recommendation"><div className="recommend-top"><span><Sparkles/> NEXT BEST ACTION</span><small>약 7분</small></div><h2>{dashboard.recommendation.title}</h2><p>{dashboard.recommendation.rationale}</p>{feedbackDone?<div className="feedback-complete"><Check/> 피드백을 반영했어요</div>:<div className="recommend-actions"><button className="primary" onClick={()=>onFeedback(true)}><ThumbsUp/> 해봤고 도움 됐어요</button><button onClick={()=>onFeedback(false)} aria-label="도움이 되지 않았어요"><ThumbsDown/></button></div>}</div>:<button className="empty-recommendation" onClick={onCheckIn}><Plus/> 지금 상태를 기록하면 맞춤 행동을 제안해요</button>}
  </aside>
  <section className="timeline-strip"><div className="strip-head"><span>TODAY'S SIGNAL STORY</span><b>{dashboard.timeline.length}개의 의미 있는 변화</b></div><div className="timeline-cards">{dashboard.timeline.slice(-3).map(item=><TimelineCard key={item.id} item={item}/>)}</div></section>
 </div>
}

function Metric({icon,label,value,trend}:{icon:React.ReactNode;label:string;value:string;trend:string}){return <div className="metric"><span>{icon}{label}</span><b>{value}</b><small>{trend}</small></div>}

function TimelineCard({item}:{item:TimelineItem}){const icon:Record<TimelineKind,React.ReactNode>={sleep:<MoonStar/>,checkin:<Watch/>,recovery:<Sparkles/>,activity:<Footprints/>,insight:<BrainCircuit/>};return <article className={`timeline-card ${item.kind}`}><div className="timeline-icon">{icon[item.kind]}</div><div><span>{item.time} {item.userConfirmed&&<i>확인됨</i>}</span><b>{item.title}</b><p>{item.detail}</p></div></article>}

function TimelineView({items,onCheckIn}:{items:TimelineItem[];onCheckIn:()=>void}){return <div className="page-view"><div className="page-heading"><div><span>SIGNAL STORY</span><h1>오늘의 타임라인</h1><p>기기 데이터와 직접 입력을 섞지 않고, 근거와 확인 상태를 함께 보여줘요.</p></div><button className="page-action" onClick={onCheckIn}><Plus/> 새 체크인</button></div>{items.length?<div className="timeline-list">{items.map((item,index)=><div className="timeline-row" key={item.id}><div className="timeline-axis"><span>{item.time}</span><i/>{index<items.length-1&&<b/>}</div><TimelineCard item={item}/></div>)}</div>:<div className="empty-state"><History/><h2>아직 오늘의 기록이 없어요</h2><p>30초 체크인으로 첫 신호를 남겨보세요.</p><button onClick={onCheckIn}>상태 기록하기</button></div>}</div>}

function ReportView({report}:{report:WeeklyReport}){
 const bars=[52,70,44,82,61,74,48];
 return <div className="page-view report-view"><div className="page-heading"><div><span>WEEKLY PATTERN REPORT</span><h1>이번 주, 무엇이 달랐을까요?</h1><p>단정 대신 반복된 신호와 회복에 도움이 된 행동을 보여줘요.</p></div><div className="week-chip">{weekRange()}</div></div><div className="report-grid"><section className="report-hero"><div><span>WELLNESS MOMENTUM</span><b>{Math.round(report.improvementRate)}%</b><small>회복 체크인 비율</small></div><div className="weekly-chart">{bars.map((height,index)=><div key={index}><i style={{height:`${height}%`}} className={index===5?'peak':''}/><span>{['월','화','수','목','금','토','일'][index]}</span></div>)}</div></section><section className="report-summary"><span>이번 주 요약</span><h2>{report.insights}</h2><div><small>체크인</small><b>{report.totalCheckIns}회</b></div><div><small>가장 잦은 상태</small><b>{statusLabel[report.topStatus??'']??'기록 없음'}</b></div><div><small>주요 맥락</small><b>{causeLabel[report.topCause??'']??'기록 없음'}</b></div></section><section className="patterns"><span>PATTERN INTELLIGENCE</span>{report.patterns.map((pattern,index)=><article key={pattern}><i>0{index+1}</i><p>{translatePattern(pattern)}</p></article>)}</section><section className="trust-card"><ShieldCheck/><div><b>이 인사이트를 믿을 수 있는 이유</b><p>개인 기준선, 직접 체크인, 추천 피드백만 사용했어요. 의료적 판단이나 다른 사용자와의 비교는 하지 않습니다.</p></div></section></div></div>
}

function PrivacyView({mode,account,profile,memories,onPair,onRebuild,onAdd,onDelete}:{mode:ConnectionMode;account:WebSession|null;profile:PersonalizationProfile|null;memories:UserMemory[];onPair:(code:string)=>Promise<void>;onRebuild:()=>void;onAdd:(type:'PREFERENCE'|'GOAL',summary:string)=>Promise<void>;onDelete:()=>void}){
 const[memoryText,setMemoryText]=useState('');const[memoryType,setMemoryType]=useState<'PREFERENCE'|'GOAL'>('PREFERENCE');const[saving,setSaving]=useState(false);const[pairCode,setPairCode]=useState('');const[pairing,setPairing]=useState(false);
 async function submitMemory(event:FormEvent){event.preventDefault();const clean=memoryText.trim();if(!clean)return;setSaving(true);await onAdd(memoryType,clean);setMemoryText('');setSaving(false)}
 async function submitPair(event:FormEvent){event.preventDefault();const clean=pairCode.trim();if(!clean)return;setPairing(true);await onPair(clean);setPairCode('');setPairing(false)}
 const memoryLabel:Record<UserMemory['type'],string>={TRIGGER_PATTERN:'반복 맥락',RECOVERY_STRATEGY:'회복 피드백',PREFERENCE:'선호',GOAL:'목표'};
 return <div className="page-view privacy-view"><div className="page-heading"><div><span>PRIVACY & PERSONAL MEMORY</span><h1>AI가 무엇을 기억하는지 직접 확인하세요</h1><p>범용 모델을 재학습하지 않고, 이 계정의 근거 있는 패턴만 개인화 컨텍스트로 사용해요.</p></div><button className="page-action" onClick={onRebuild}><RefreshCw/> 기록에서 다시 학습</button></div>
  <section className="device-pairing"><div><Watch/><span>DEVICE ACCOUNT</span><b>{account?`사용자 ${account.userId}`:'서버 연결 대기'}</b><p>iPhone 설정에 표시된 연결 코드를 입력하면 Watch·iPhone·웹이 같은 데이터와 AI 메모리를 사용합니다.</p></div><form onSubmit={submitPair}><input aria-label="iPhone 연결 코드" maxLength={8} value={pairCode} onChange={event=>setPairCode(event.target.value.toUpperCase())} placeholder="6자리 연결 코드"/><button disabled={pairing||!pairCode.trim()}>{pairing?<RefreshCw className="rotating"/>:<Signal/>} 같은 계정으로 연결</button><small>이 웹의 추가 기기 코드: {account?.pairingCode??'—'}</small></form></section>
  <section className="learning-console">
   <div className="learning-score"><BrainCircuit/><div><span>PERSONALIZATION ENGINE</span><b>{profile?.personalized?'개인화 활성':'학습 대기'}</b><p>활성 메모리 {profile?.activeMemoryCount??0}개 · 누적 근거 {profile?.evidenceCount??0}건 · 도움 된 전략 {profile?.helpfulStrategyCount??0}개</p></div></div>
   <form className="memory-form" onSubmit={submitMemory}><div><button type="button" className={memoryType==='PREFERENCE'?'on':''} onClick={()=>setMemoryType('PREFERENCE')}>내 선호</button><button type="button" className={memoryType==='GOAL'?'on':''} onClick={()=>setMemoryType('GOAL')}>내 목표</button></div><input maxLength={600} value={memoryText} onChange={event=>setMemoryText(event.target.value)} placeholder="예: 강한 운동보다 짧은 산책을 선호해요"/><button disabled={saving||!memoryText.trim()}><Plus/> 기억하기</button></form>
   <div className="memory-list">{memories.length?memories.slice(0,8).map(memory=><article key={memory.id}><span>{memoryLabel[memory.type]}</span><p>{memory.summary}</p><small>신뢰도 {Math.round(memory.confidence*100)}% · 근거 {memory.evidenceCount}건</small></article>):<div className="memory-empty">체크인과 추천 피드백이 쌓이면 여기에 개인화 근거가 표시됩니다.</div>}</div>
  </section>
  <div className="privacy-grid"><article><div className="privacy-icon"><HeartPulse/></div><span>HEALTHKIT</span><h2>원본은 기기에,<br/>파생 요약만 동기화</h2><p>허용한 건강 원본 샘플은 iPhone과 Watch에서만 읽고, 사용자가 켠 경우 화면용 일별 요약만 서버로 동기화해요.</p></article><article><div className="privacy-icon"><LockKeyhole/></div><span>ACCOUNT MEMORY</span><h2>서버에는 설명 가능한<br/>개인 메모리만</h2><p>체크인과 피드백에서 만들어진 패턴은 근거 수와 신뢰도를 함께 저장하고 AI 요청 때만 사용해요.</p></article><article><div className="privacy-icon"><ShieldCheck/></div><span>USER CONTROL</span><h2>언제든 기록과 기억을<br/>함께 삭제</h2><p>전체 삭제 시 체크인, 파생 건강 요약, 대화, 추천 피드백, 개인화 메모리까지 모두 제거해요.</p></article></div>
  <div className="data-status"><div><i className={mode}/><span>현재 연결</span><b>{mode==='live'?'로컬 API · 영구 저장':'복원력 있는 데모 데이터'}</b></div><div><span>AI 사용 범위</span><b>계정별 개인화 · 범용 학습 제외</b></div><button onClick={onDelete}><Trash2/> 기록과 AI 메모리 삭제</button></div><div className="safety-note"><BrainCircuit/><p><b>Morrow는 의료기기나 응급 서비스가 아닙니다.</b> 증상이 지속되거나 긴급한 도움이 필요하면 의료 전문가 또는 지역 응급기관에 연락하세요.</p></div></div>
}

function CheckInModal({userId,onClose,onSave}:{userId:string;onClose:()=>void;onSave:(input:CheckInInput)=>Promise<void>}){
 const[status,setStatus]=useState<CheckInStatus>('TIRED');const[cause,setCause]=useState<CheckInCause>('SLEEP');const[note,setNote]=useState('');const[saving,setSaving]=useState(false);
 async function submit(event:FormEvent){event.preventDefault();setSaving(true);await onSave({userId,status,cause,note:note.trim(),source:'WEB',recordedAt:new Date().toISOString()});setSaving(false)}
 return <div className="modal-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)onClose()}}><form className="checkin-modal" onSubmit={submit}><div className="modal-head"><div><span>30-SECOND CHECK-IN</span><h2>지금 어떤 상태인가요?</h2></div><button type="button" onClick={onClose} aria-label="닫기"><X/></button></div><div className="status-options">{statusOptions.map(([value,label,description])=><button type="button" key={value} className={status===value?'selected':''} onClick={()=>setStatus(value)}><i>{status===value&&<Check/>}</i><b>{label}</b><span>{description}</span></button>)}</div><label className="field"><span>무엇과 가장 관련 있나요?</span><div className="cause-options">{causeOptions.map(([value,label])=><button type="button" key={value} className={cause===value?'selected':''} onClick={()=>setCause(value)}>{label}</button>)}</div></label><label className="field"><span>필요하면 맥락을 남겨주세요 <small>선택</small></span><textarea maxLength={500} value={note} onChange={event=>setNote(event.target.value)} placeholder="예: 어제 마감 때문에 늦게 잠들었어요"/><small>{note.length}/500</small></label><button className="save-checkin" disabled={saving}>{saving?<><RefreshCw className="rotating"/> 흐름에 반영 중</>:<><Check/> 체크인 저장</>}</button><p className="modal-foot"><LockKeyhole/> 직접 입력은 생체 신호보다 우선하며 언제든 삭제할 수 있어요.</p></form></div>
}

function LoadingView(){return <div className="loading-view"><div className="loading-orb"/><span>개인 기준선을 연결하고 있어요</span></div>}

function WebLoginView({onLogin}:{onLogin:(username:string,password:string)=>Promise<void>}){
 const[username,setUsername]=useState('사용자');const[password,setPassword]=useState('');const[loading,setLoading]=useState(false);const[error,setError]=useState('');
 async function submit(event:FormEvent){event.preventDefault();if(!username.trim()||!password)return;setLoading(true);setError('');try{await onLogin(username.trim(),password)}catch{setError('사용자 이름 또는 비밀번호를 확인해 주세요.')}finally{setLoading(false)}}
 return <main className="login-shell"><div className="login-glow"/><section className="login-card"><div className="login-brand"><i>M</i><div><b>MORROW</b><span>HACKATHON DEMO LOGIN</span></div></div><div className="login-copy"><span>ONE ACCOUNT · ALL DEVICES</span><h1>당신의 흐름과<br/>다시 연결하세요</h1><p>하나의 테스트 계정으로 웹, iPhone, Apple Watch의 건강 요약과 AI 대화를 함께 사용합니다.</p></div><form onSubmit={submit}><label><span>사용자 이름</span><input autoComplete="username" value={username} onChange={event=>setUsername(event.target.value)} placeholder="사용자"/></label><label><span>비밀번호</span><input autoComplete="current-password" type="password" value={password} onChange={event=>setPassword(event.target.value)} placeholder="비밀번호 입력"/></label>{error&&<p className="login-error">{error}</p>}<button disabled={loading||!username.trim()||!password}>{loading?<RefreshCw className="rotating"/>:<LockKeyhole/>}{loading?'계정 연결 중':'로그인'}</button></form><footer><ShieldCheck/> 해커톤 시연용 단일 테스트 계정</footer></section></main>
}

function translatePattern(value:string){return value.replaceAll('LOW_FOCUS','집중 저하').replaceAll('TIRED','피로').replaceAll('TENSE','긴장').replaceAll('OK','괜찮음').replaceAll('SLEEP','수면').replaceAll('WORK','업무').replaceAll('STUDY','학업')}

function weekRange(){
 const today=new Date();const monday=new Date(today);monday.setHours(0,0,0,0);monday.setDate(today.getDate()-((today.getDay()+6)%7));const sunday=new Date(monday);sunday.setDate(monday.getDate()+6);
 return`${monday.getMonth()+1}월 ${monday.getDate()}일 — ${sunday.getMonth()+1}월 ${sunday.getDate()}일`;
}
