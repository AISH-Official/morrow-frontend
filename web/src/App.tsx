import {FormEvent,useEffect,useMemo,useRef,useState} from 'react';
import {Activity,Archive,ChevronRight,Command,HeartPulse,History,Mic,MicOff,MoonStar,Plus,Send,Settings2,ShieldCheck,Signal,Volume2,VolumeX,Watch}from'lucide-react';

type Role='ai'|'user';type Phase='idle'|'listening'|'thinking'|'speaking';
type Chat={id:number;role:Role;text:string};
type RecognitionEvent={results:ArrayLike<{0:{transcript:string};isFinal:boolean}>};
type RecognitionLike={lang:string;continuous:boolean;interimResults:boolean;start:()=>void;stop:()=>void;onresult:((e:RecognitionEvent)=>void)|null;onend:(()=>void)|null;onerror:(()=>void)|null};

const suggestions=['오늘 컨디션 어때?','잠을 잘 못 잤어','집중할 수 있게 도와줘'];
const responses=[
 '어젯밤 수면은 5시간 48분이었고, 평소보다 조금 짧았어요. 지금은 무리해서 집중하기보다 7분 정도 가볍게 움직이는 게 좋겠어요.',
 '알겠어요. 수면 부족이 오늘의 피로와 함께 나타나고 있어요. 지금 할 일을 하나만 남기고, 나머지는 잠시 미뤄볼까요?',
 '지금 상태에서는 긴 계획보다 짧은 시작이 좋아요. 15분 집중 세션을 만들고, 그동안 알림을 잠시 멈춰드릴게요.'
];

export default function App(){
 const[message,setMessage]=useState('');const[phase,setPhase]=useState<Phase>('idle');const[sound,setSound]=useState(true);
 const[chats,setChats]=useState<Chat[]>([{id:1,role:'ai',text:'좋은 저녁이에요, 수빈님.'},{id:2,role:'ai',text:'오늘은 평소보다 조금 지쳐 보여요. 지금 어떤 상태인지 이야기해 주세요.'}]);
 const recognition=useRef<RecognitionLike|null>(null);const nextId=useRef(3);const responseIndex=useRef(0);
 const particles=useMemo(()=>Array.from({length:62},(_,i)=>({left:`${(i*47)%100}%`,top:`${(i*71)%100}%`,delay:`-${(i%13)*.37}s`,size:1+(i%3)})),[]);
 const phaseText={idle:'무엇이든 이야기해 주세요',listening:'듣고 있어요',thinking:'당신의 흐름을 살펴보고 있어요',speaking:'답변하고 있어요'}[phase];

 useEffect(()=>()=>{recognition.current?.stop();window.speechSynthesis?.cancel()},[]);
 function speak(text:string){if(!sound||!('speechSynthesis'in window)){setPhase('idle');return}const utterance=new SpeechSynthesisUtterance(text);utterance.lang='ko-KR';utterance.rate=.98;utterance.pitch=.93;utterance.onend=()=>setPhase('idle');utterance.onerror=()=>setPhase('idle');window.speechSynthesis.cancel();window.speechSynthesis.speak(utterance)}
 function streamAnswer(answer:string){const id=nextId.current++;setChats(v=>[...v,{id,role:'ai',text:''}]);setPhase('speaking');let i=0;const timer=window.setInterval(()=>{i+=1;setChats(v=>v.map(x=>x.id===id?{...x,text:answer.slice(0,i)}:x));if(i>=answer.length){clearInterval(timer);speak(answer)}},18)}
 function send(text=message){const clean=text.trim();if(!clean||phase==='thinking'||phase==='speaking')return;recognition.current?.stop();window.speechSynthesis?.cancel();setChats(v=>[...v,{id:nextId.current++,role:'user',text:clean}]);setMessage('');setPhase('thinking');const answer=responses[responseIndex.current++%responses.length];window.setTimeout(()=>streamAnswer(answer),1100)}
 function toggleMic(){if(phase==='listening'){recognition.current?.stop();setPhase('idle');return}const w=window as typeof window&{webkitSpeechRecognition?:new()=>RecognitionLike;SpeechRecognition?:new()=>RecognitionLike};const Ctor=w.SpeechRecognition||w.webkitSpeechRecognition;if(!Ctor){setPhase('listening');window.setTimeout(()=>setPhase('idle'),2200);return}const rec=new Ctor();rec.lang='ko-KR';rec.continuous=false;rec.interimResults=true;rec.onresult=e=>{let value='';for(let i=0;i<e.results.length;i++)value+=e.results[i][0].transcript;setMessage(value)};rec.onend=()=>setPhase(p=>p==='listening'?'idle':p);rec.onerror=()=>setPhase('idle');recognition.current=rec;setPhase('listening');rec.start()}
 return <div className={`assistant-shell phase-${phase}`}>
  <div className="atmosphere"/><div className="grid-floor"/>
  <aside className="rail"><div className="mark">M</div><nav><button className="on"><Command/></button><button><History/></button><button><Archive/></button></nav><button className="settings"><Settings2/></button></aside>
  <header className="topbar"><div className="identity"><div className="status-dot"/><div><b>MORROW</b><span>PERSONAL WELLNESS INTELLIGENCE</span></div></div><div className="system-status"><span><Signal/> SYSTEM ONLINE</span><span><ShieldCheck/> PRIVATE MODE</span><button><Plus/> NEW SESSION</button></div></header>
  <main className="experience">
   <section className="sensor-card sleep"><div className="sensor-head"><MoonStar/> LAST NIGHT</div><b>5h 48m</b><span>평균보다 1시간 12분 적어요</span><div className="tiny-bars">{[6,8,5,10,9,13,8,7,11,5,6,8,4,6,7,5].map((x,i)=><i key={i} style={{height:x}}/>)}</div></section>
   <section className="sensor-card pulse"><div className="sensor-head"><HeartPulse/> CURRENT SIGNAL</div><b>72 <small>BPM</small></b><span>안정 시 심박 · 평소보다 +6</span><div className="pulse-line"><i/><i/><i/><i/><i/><i/><i/></div></section>
   <section className="dialogue">
    <div className="phase-label"><i/>{phaseText}</div>
    <div className="ai-core" aria-label={phaseText}>
     <div className="outer-orbit"><i/><i/><i/></div><div className="tech-ring ring-one"/><div className="tech-ring ring-two"/><div className="scan-line"/>
     <div className="core-halo"/><div className="core-surface"><div className="wave">{Array.from({length:29},(_,i)=><i key={i} style={{height:`${13+Math.abs(14-i)*1.6+(i%4)*5}px`,animationDelay:`-${i*.06}s`}}/>)}</div><div className="thinking-dots"><i/><i/><i/></div></div>
     {particles.map((p,i)=><i className="particle" key={i} style={{left:p.left,top:p.top,width:p.size,height:p.size,animationDelay:p.delay}}/>)}
    </div>
    <div className="conversation">{chats.slice(-3).map(item=><p key={item.id} className={item.role}>{item.text}{item.role==='ai'&&phase==='speaking'&&item.id===chats.at(-1)?.id?<i className="cursor"/>:null}</p>)}</div>
    <div className="suggestions">{phase==='idle'&&suggestions.map(x=><button key={x} onClick={()=>send(x)}>{x}<ChevronRight/></button>)}</div>
   </section>
   <section className="sensor-card watch-card"><div className="sensor-head"><Watch/> APPLE WATCH</div><div className="watch-row"><div className="watch-icon"><Activity/></div><div><b>연결됨</b><span>2분 전에 동기화</span></div></div><div className="signal-row"><span>HRV <b>41 ms</b></span><span>STEPS <b>4,821</b></span></div></section>
   <form className="composer" onSubmit={(e:FormEvent)=>{e.preventDefault();send()}}><button aria-label={phase==='listening'?'음성 듣기 중지':'음성으로 말하기'} type="button" className={`mic ${phase==='listening'?'active':''}`} onClick={toggleMic}>{phase==='listening'?<MicOff/>:<Mic/>}</button><div><input value={message} onChange={e=>setMessage(e.target.value)} placeholder={phase==='listening'?'듣고 있어요...':'Morrow에게 이야기하세요'} disabled={phase==='thinking'||phase==='speaking'}/><span>{phase==='listening'?'말을 마치면 자동으로 입력됩니다':phase==='thinking'?'HealthKit 흐름과 대화를 연결하는 중':'Enter로 보내기 · 모든 대화는 안전하게 보호됩니다'}</span></div><button aria-label={sound?'음성 답변 끄기':'음성 답변 켜기'} className="sound" type="button" onClick={()=>{setSound(v=>!v);window.speechSynthesis?.cancel()}}>{sound?<Volume2/>:<VolumeX/>}</button><button aria-label="메시지 보내기" className="send" type="submit"><Send/></button></form>
  </main><footer><span>WELLNESS SUPPORT — NOT MEDICAL DIAGNOSIS</span><span className="session"><i/> SESSION ENCRYPTED</span></footer>
 </div>
}
