import{useState}from'react';
import{Activity,ArrowLeft,ChevronDown,ChevronRight,ChevronUp,HeartPulse,Mic,MoonStar,MoreHorizontal,ShieldCheck,Sparkles,Watch,Wind}from'lucide-react';

const moods=['괜찮아요','피곤해요','긴장돼요'];

export default function DevicePreview(){
 const[watchMood,setWatchMood]=useState('피곤해요');const[watchPage,setWatchPage]=useState(0);const[phoneListening,setPhoneListening]=useState(false);
 const moveCrown=(direction:number)=>setWatchPage(page=>Math.max(0,Math.min(2,page+direction)));
 const watchOnly=new URLSearchParams(location.search).get('watch')==='1';
 return <div className={`preview-page ${watchOnly?'watch-only-preview':''}`}>
  <div className="preview-glow"/><header className="preview-header"><a href={watchOnly?'/device-preview':'/'}><ArrowLeft/>{watchOnly?'전체 기기':'PC 화면'}</a><div><b>{watchOnly?'WATCH EXPERIENCE':'DEVICE EXPERIENCE'}</b><span>{watchOnly?'Crown-first glanceable interaction':'iPhone & Apple Watch design preview'}</span></div><div className="preview-badge"><ShieldCheck/> WELLNESS ONLY</div></header>
  <main className="devices-stage">
   {!watchOnly&&<section className="device-column"><div className="device-label"><span>01</span><div><b>iPhone</b><small>분석 · 대화 · 회복 가이드</small></div></div>
    <div className={`iphone ${phoneListening?'phone-listening':''}`}><div className="iphone-screen"><div className="dynamic-island"/><div className="phone-top"><span>9:41</span><b>MORROW</b><MoreHorizontal/></div>
     <div className="phone-content"><p className="phone-date">8월 3일 월요일</p><h1>좋은 저녁이에요,<br/>수빈님.</h1><div className="mini-core"><div className="mini-ring one"/><div className="mini-ring two"/><div className="mini-orb"><div className="mini-wave">{Array.from({length:15},(_,i)=><i key={i} style={{height:12+(i%5)*5}}/>)}</div></div></div>
      <div className="phone-ai-copy"><b>{phoneListening?'듣고 있어요':'오늘은 조금 지쳐 보여요'}</b><span>{phoneListening?'편하게 말씀해 주세요':'수면이 평소보다 1시간 12분 짧았어요.'}</span></div>
      <div className="phone-metrics"><div><MoonStar/><span>수면<b>5h 48m</b></span></div><div><HeartPulse/><span>심박<b>72 bpm</b></span></div><div><Activity/><span>HRV<b>41 ms</b></span></div></div>
      <div className="phone-recommend"><div className="recommend-icon"><Sparkles/></div><div><small>지금의 추천</small><b>7분 동안 가볍게 걸어보세요</b></div><ChevronRight/></div>
     </div><div className="phone-composer"><button onClick={()=>setPhoneListening(v=>!v)}><Mic/></button><span>{phoneListening?'음성을 듣고 있어요...':'Morrow에게 이야기하세요'}</span></div><div className="home-indicator"/></div></div>
   </section>}

   <section className="device-column watch-column"><div className="device-label"><span>02</span><div><b>Apple Watch</b><small>감지 · 체크인 · 즉시 대응</small></div></div>
    <div className="watch-wrap"><div className="watch-crown"><button aria-label="이전 화면" onClick={()=>moveCrown(-1)}><ChevronUp/></button><i/><button aria-label="다음 화면" onClick={()=>moveCrown(1)}><ChevronDown/></button></div><div className="watch-body"><div className="watch-screen native-watch"><div className="watch-status"><i/><span>Morrow</span><small>19:42</small></div><div className="page-dots">{[0,1,2].map(page=><i className={watchPage===page?'active':''}key={page}/>)}</div>
     {watchPage===0&&<div className="watch-page overview-page"><small>오늘의 상태</small><div className="load-ring"><div><b>68</b><span>조금 높음</span></div></div><p>수면이 짧았지만<br/>회복 흐름은 안정적이에요.</p><div className="glance-metrics"><span><MoonStar/><b>5h 48m</b></span><span><HeartPulse/><b>72</b></span></div><button className="watch-primary"onClick={()=>setWatchPage(1)}>상태 기록</button></div>}
     {watchPage===1&&<div className="watch-page checkin-page"><small>빠른 체크인</small><h2>지금 어떤가요?</h2><div className="native-moods">{moods.map((m,index)=><button className={watchMood===m?'active':''}onClick={()=>setWatchMood(m)}key={m}><i>{index===0?'✓':index===1?'−':'!'}</i><span>{m}</span></button>)}</div><button className="watch-primary"onClick={()=>setWatchPage(2)}>기록 완료</button></div>}
     {watchPage===2&&<div className="watch-page recovery-page"><small>추천 활동</small><div className="breathe-orb"><Wind/></div><h2>1분 호흡</h2><p>손목의 진동에 맞춰<br/>천천히 호흡해 보세요.</p><button className="watch-primary">시작</button></div>}
    </div></div></div>
    <div className="crown-hint"><span>Digital Crown</span><div><button onClick={()=>moveCrown(-1)}><ChevronUp/></button><button onClick={()=>moveCrown(1)}><ChevronDown/></button></div></div>
    <div className="watch-detail"><Watch/><div><b>세로 페이지 탐색</b><span>Digital Crown으로 상태·체크인·회복 화면을 빠르게 이동합니다.</span></div></div>
   </section>
  </main>
  <footer className="preview-footer"><span>두 화면은 브라우저에서 확인하는 디자인 프리뷰입니다.</span><span>SWIFTUI IMPLEMENTATION READY</span></footer>
 </div>
}
