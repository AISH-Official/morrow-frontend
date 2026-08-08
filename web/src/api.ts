import type{AssistantResult,CheckInInput,ConnectionMode,Dashboard,PersonalizationProfile,TimelineItem,TimelineKind,UserMemory,WeeklyReport}from'./types';

const API_ROOT='/api/v1';
const REQUEST_TIMEOUT=5000;

export const demo:Dashboard={
 wellnessLoad:'HIGHER_THAN_USUAL',
 score:68,
 metrics:{sleepMinutes:348,restingHeartRate:72,hrv:41,steps:4821},
 timeline:[
  {id:'sleep',time:'08:10',title:'수면 회복이 평소보다 낮음',detail:'최근 7일 평균보다 1시간 12분 짧았어요.',kind:'sleep',userConfirmed:false},
  {id:'checkin',time:'13:40',title:'Watch 상태 체크인',detail:'피로 · 원인: 수면 부족',kind:'checkin',userConfirmed:true},
  {id:'recovery',time:'15:20',title:'10분 걷기 완료',detail:'상태가 조금 나아졌다고 기록했어요.',kind:'recovery',userConfirmed:true}
 ],
 recommendation:{id:'walk-7',title:'7분 동안 가볍게 걸어보세요',rationale:'비슷한 피로 상태에서 짧은 걷기가 가장 자주 도움이 됐습니다.'},
 disclaimer:'의료 진단이 아닌 일상 웰니스 분석입니다.'
};

export const demoReport:WeeklyReport={
 totalCheckIns:12,
 topStatus:'TIRED',
 topCause:'SLEEP',
 improvementRate:67,
 patterns:['화요일과 목요일 오후에 피로 기록이 집중됐어요.','6시간 미만 수면 다음 날 체크인이 2.4배 늘었어요.','짧은 걷기 후 3번 중 2번 상태가 나아졌어요.'],
 insights:'이번 주는 수면이 짧은 날에 피로가 반복됐지만, 짧은 움직임으로 회복한 흐름이 확인됐어요.'
};

async function request<T>(path:string,init?:RequestInit):Promise<T>{
 const controller=new AbortController();
 const timer=window.setTimeout(()=>controller.abort(),REQUEST_TIMEOUT);
 try{
  const response=await fetch(`${API_ROOT}${path}`,{
   ...init,
   signal:controller.signal,
   headers:{'Content-Type':'application/json',...init?.headers}
  });
  if(!response.ok)throw new Error(`API ${response.status}`);
  if(response.status===204)return undefined as T;
  return await response.json() as T;
 }finally{window.clearTimeout(timer)}
}

function normalizeKind(value:string):TimelineKind{
 const kind=value.toLowerCase();
 return(['sleep','checkin','recovery','activity','insight']as TimelineKind[]).includes(kind as TimelineKind)?kind as TimelineKind:'insight';
}

function normalizeDashboard(value:Dashboard):Dashboard{
 return{...value,timeline:(value.timeline??[]).map(item=>({...item,kind:normalizeKind(item.kind)})),recommendation:value.recommendation??null};
}

export async function getDashboard():Promise<{data:Dashboard;mode:ConnectionMode}>{
 try{return{data:normalizeDashboard(await request<Dashboard>('/dashboard?userId=default-user')),mode:'live'}}
 catch{return{data:demo,mode:'demo'}}
}

export async function getWeeklyReport():Promise<WeeklyReport>{
 try{return await request<WeeklyReport>('/reports/weekly?userId=default-user')}
 catch{return demoReport}
}

export async function sendAssistantMessage(content:string):Promise<AssistantResult>{
 try{
  return await request<AssistantResult>('/assistant/messages',{method:'POST',body:JSON.stringify({userId:'default-user',content})});
 }catch{return{content:localAssistantResponse(content),aiMode:'LOCAL',personalizationEvidenceCount:0,personalized:false}}
}

export async function getPersonalization():Promise<{profile:PersonalizationProfile;memories:UserMemory[]}>{
 try{return{profile:await request<PersonalizationProfile>('/personalization/profile?userId=default-user'),memories:await request<UserMemory[]>('/personalization/memories?userId=default-user')}}
 catch{return{profile:{userId:'default-user',activeMemoryCount:0,evidenceCount:0,helpfulStrategyCount:0,avoidStrategyCount:0,lastLearnedAt:null,personalized:false},memories:[]}}
}

export async function rebuildPersonalization():Promise<PersonalizationProfile>{return request<PersonalizationProfile>('/personalization/rebuild?userId=default-user',{method:'POST'})}

export async function addPersonalMemory(type:'PREFERENCE'|'GOAL',summary:string):Promise<UserMemory>{return request<UserMemory>('/personalization/memories',{method:'POST',body:JSON.stringify({userId:'default-user',type,summary})})}

export async function createCheckIn(input:CheckInInput):Promise<{id:string}>{
 try{return await request<{id:string}>('/check-ins',{method:'POST',body:JSON.stringify(input)})}
 catch(error){console.warn('Check-in API unavailable; continuing locally.',error);return{id:`local-${Date.now()}`}}
}

export async function submitRecommendationFeedback(id:string,helpful:boolean):Promise<void>{
 if(id.startsWith('walk-'))return;
 await request(`/recommendations/${id}/feedback`,{method:'POST',body:JSON.stringify({completed:true,helpful,note:helpful?'도움이 됐어요':'다른 제안이 필요해요'})});
}

export async function clearWellnessData():Promise<void>{
 await request('/users/me/data?userId=default-user',{method:'DELETE'});
}

export function appendLocalCheckIn(current:Dashboard,input:CheckInInput,id:string):Dashboard{
 const labels:Record<CheckInInput['status'],string>={OK:'괜찮음',TENSE:'긴장',TIRED:'피로',LOW_FOCUS:'집중 저하',UNCOMFORTABLE:'불편함'};
 const causes:Record<CheckInInput['cause'],string>={SLEEP:'수면',WORK:'업무',STUDY:'학업',RELATIONSHIP:'관계',PHYSICAL:'신체',UNKNOWN:'잘 모르겠음'};
 const now=new Date();
 const item:TimelineItem={id,time:now.toLocaleTimeString('ko-KR',{hour:'2-digit',minute:'2-digit',hour12:false}),title:'웹 상태 체크인',detail:`${labels[input.status]} · 원인: ${causes[input.cause]}${input.note?` · ${input.note}`:''}`,kind:'checkin',userConfirmed:true};
 const penalty=input.status==='OK'?2:5;
 return{...current,score:Math.max(0,Math.min(100,current.score+(input.status==='OK'?penalty:-penalty))),timeline:[...current.timeline,item]};
}

function localAssistantResponse(message:string):string{
 if(/죽|자해|사라지고|끝내고/.test(message))return'지금 혼자 버티지 않아도 괜찮아요. 즉시 위험하다면 119 또는 112에 연락하고, 자살예방상담전화 109에서 24시간 도움을 받을 수 있어요. 가능하면 지금 믿을 수 있는 사람에게도 곁에 있어 달라고 알려주세요.';
 if(/잠|수면|피곤/.test(message))return'어젯밤 수면은 평소보다 1시간 12분 짧았어요. 지금은 의지로 밀어붙이기보다 물 한 잔을 마시고 7분만 가볍게 움직여 보는 게 좋아요.';
 if(/집중|일|공부/.test(message))return'지금 상태에서는 긴 계획보다 짧은 시작이 좋아요. 할 일을 하나만 고르고 15분 집중한 뒤, 컨디션을 다시 확인해 볼까요?';
 if(/긴장|불안|스트레스/.test(message))return'긴장이 올라온 걸 알아차린 것만으로도 좋은 시작이에요. 어깨의 힘을 빼고 4초 들이마시고 6초 내쉬는 호흡을 세 번 해보세요.';
 return'지금 느끼는 상태를 한 단어로 기록해 볼까요? 최근 흐름과 함께 살펴보고, 부담 없이 바로 할 수 있는 행동 하나를 제안할게요.';
}
