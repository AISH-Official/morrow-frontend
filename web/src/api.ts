import type{AssistantResult,CheckInInput,Dashboard,PersonalizationProfile,TimelineKind,UserMemory,WeeklyReport}from'./types';

const API_ROOT=import.meta.env.VITE_API_BASE_URL||'/api/v1';
const REQUEST_TIMEOUT=30000;
const SESSION_KEY='morrow.web.session.v2';
const LEGACY_SESSION_KEY='morrow.web.session.v1';
const INSTALLATION_KEY='morrow.web.installation.v1';

export type WebSession={userId:string;accessToken:string;pairingCode:string;deviceId:string;platform:string};
export type ConnectedDevice={id:string;deviceId:string;deviceName:string;platform:'IOS'|'WATCHOS'|'WEB';lastSeenAt:string};

export class SessionExpiredError extends Error{
 constructor(){super('로그인이 만료되었습니다.');this.name='SessionExpiredError'}
}

export class ApiRequestError extends Error{
 constructor(readonly status:number){super(`API ${status}`);this.name='ApiRequestError'}
}

export function isSessionExpired(error:unknown):boolean{return error instanceof SessionExpiredError}

async function rawRequest<T>(path:string,init?:RequestInit,authenticated=true):Promise<T>{
 const controller=new AbortController();
 const timer=window.setTimeout(()=>controller.abort(),REQUEST_TIMEOUT);
 try{
  const session=authenticated?storedSession():null;
  if(authenticated&&!session)throw new SessionExpiredError();
  const response=await fetch(`${API_ROOT}${path}`,{
   ...init,
   signal:controller.signal,
   headers:{'Content-Type':'application/json',...(session?{Authorization:`Bearer ${session.accessToken}`}:{}) ,...init?.headers}
  });
  if(response.status===401&&authenticated){window.localStorage.removeItem(SESSION_KEY);throw new SessionExpiredError()}
  if(!response.ok)throw new ApiRequestError(response.status);
  if(response.status===204)return undefined as T;
  return await response.json() as T;
 }finally{window.clearTimeout(timer)}
}

function storedSession():WebSession|null{
 window.localStorage.removeItem(LEGACY_SESSION_KEY);
 try{
  const value=window.localStorage.getItem(SESSION_KEY);if(!value)return null;
  const parsed=JSON.parse(value) as Partial<WebSession>;
  if(!parsed.userId||!parsed.accessToken||!parsed.pairingCode||!parsed.deviceId||!parsed.platform){window.localStorage.removeItem(SESSION_KEY);return null}
  return parsed as WebSession;
 }catch{window.localStorage.removeItem(SESSION_KEY);return null}
}

export function getStoredWebSession():WebSession|null{return storedSession()}

function installationId():string{
 const existing=window.localStorage.getItem(INSTALLATION_KEY);if(existing)return existing;
 const value=crypto.randomUUID();window.localStorage.setItem(INSTALLATION_KEY,value);return value;
}

function saveSession(value:WebSession):WebSession{window.localStorage.setItem(SESSION_KEY,JSON.stringify(value));return value}

export async function getWebSession():Promise<WebSession>{
 const stored=storedSession();
 if(!stored)throw new SessionExpiredError();
 return stored;
}

export async function pairWebSession(pairingCode:string):Promise<WebSession>{
 const value=await rawRequest<WebSession>('/auth/pair',{method:'POST',body:JSON.stringify({pairingCode,deviceId:`web-${installationId()}`,deviceName:navigator.userAgent.includes('Mobile')?'Mobile Web':'Web Browser',platform:'WEB'})});
 return saveSession(value);
}

export async function loginWebSession(accountId:string):Promise<WebSession>{
 const value=await rawRequest<WebSession>('/auth/account',{method:'POST',body:JSON.stringify({accountId,deviceId:`web-${installationId()}`,deviceName:navigator.userAgent.includes('Mobile')?'Mobile Web':'Web Browser',platform:'WEB'})},false);
 return saveSession(value);
}

export async function logoutWebSession():Promise<void>{
 const session=storedSession();
 window.localStorage.removeItem(SESSION_KEY);
 if(!session)return;
 const controller=new AbortController();
 const timer=window.setTimeout(()=>controller.abort(),REQUEST_TIMEOUT);
 try{
  await fetch(`${API_ROOT}/auth/logout`,{method:'POST',signal:controller.signal,headers:{Authorization:`Bearer ${session.accessToken}`}});
 }catch{
  // Network failures must not trap someone in a signed-in state on this browser.
 }finally{
  window.clearTimeout(timer);
 }
}

async function request<T>(path:string,init?:RequestInit):Promise<T>{return rawRequest<T>(path,init,true)}

async function userPath(path:string):Promise<string>{const session=await getWebSession();return `${path}${path.includes('?')?'&':'?'}userId=${encodeURIComponent(session.userId)}`}

function normalizeKind(value:string):TimelineKind{
 const kind=value.toLowerCase();
 return(['sleep','checkin','recovery','activity','insight']as TimelineKind[]).includes(kind as TimelineKind)?kind as TimelineKind:'insight';
}

function normalizeDashboard(value:Dashboard):Dashboard{
 return{...value,hasHealthData:value.hasHealthData??Object.values(value.metrics??{}).some(item=>Number(item)>0),scoreConfidence:value.scoreConfidence??'LOW',scoreReasons:value.scoreReasons??[],lastUpdatedAt:value.lastUpdatedAt??null,timeline:(value.timeline??[]).map(item=>({...item,kind:normalizeKind(item.kind)})),recommendation:value.recommendation??null};
}

export async function getDashboard():Promise<Dashboard>{return normalizeDashboard(await request<Dashboard>(await userPath('/dashboard')))}

export async function getWeeklyReport():Promise<WeeklyReport>{return request<WeeklyReport>(await userPath('/reports/weekly'))}

export async function sendAssistantMessage(content:string):Promise<AssistantResult>{
 try{
  const session=await getWebSession();const result=await request<AssistantResult>('/assistant/messages',{method:'POST',body:JSON.stringify({userId:session.userId,content})});
  return{...result,content:normalizeAssistantText(result.content)};
 }catch(error){if(isSessionExpired(error))throw error;return{content:localAssistantResponse(content),aiMode:'LOCAL',personalizationEvidenceCount:0,personalized:false}}
}

export async function clearAssistantConversation():Promise<void>{await request(await userPath('/assistant/messages'),{method:'DELETE'})}

function normalizeAssistantText(content:string):string{return content.replace(/[\"“”„‟＂]/g,'').trim()}

export async function getPersonalization():Promise<{profile:PersonalizationProfile;memories:UserMemory[]}>{
 return{profile:await request<PersonalizationProfile>(await userPath('/personalization/profile')),memories:await request<UserMemory[]>(await userPath('/personalization/memories'))};
}

export async function getConnectedDevices():Promise<ConnectedDevice[]>{return request<ConnectedDevice[]>('/auth/devices')}
export async function revokeConnectedDevice(id:string):Promise<void>{await request(`/auth/devices/${id}`,{method:'DELETE'})}
export async function getAiHealthConsent():Promise<boolean>{return(await request<{consent:boolean}>('/privacy/ai-health-consent')).consent}
export async function setAiHealthConsent(consent:boolean):Promise<boolean>{return(await request<{consent:boolean}>('/privacy/ai-health-consent',{method:'PATCH',body:JSON.stringify({consent})})).consent}
export async function exportAccountData():Promise<unknown>{
 const[dashboard,weekly,personalization,devices,consent,checkIns,messages]=await Promise.all([
  getDashboard(),getWeeklyReport(),getPersonalization(),getConnectedDevices(),getAiHealthConsent(),
  request<unknown[]>(await userPath('/check-ins')),request<unknown[]>(await userPath('/assistant/messages'))
 ]);
 return{exportedAt:new Date().toISOString(),dashboard,weekly,personalization,devices,aiHealthConsent:consent,checkIns,messages};
}

export async function rebuildPersonalization():Promise<PersonalizationProfile>{return request<PersonalizationProfile>(await userPath('/personalization/rebuild'),{method:'POST'})}

export async function addPersonalMemory(type:'PREFERENCE'|'GOAL',summary:string):Promise<UserMemory>{const session=await getWebSession();return request<UserMemory>('/personalization/memories',{method:'POST',body:JSON.stringify({userId:session.userId,type,summary})})}

export async function createCheckIn(input:CheckInInput):Promise<{id:string}>{
 const session=await getWebSession();
 return request<{id:string}>('/check-ins',{method:'POST',body:JSON.stringify({...input,userId:session.userId})});
}

export async function submitRecommendationFeedback(id:string,helpful:boolean):Promise<void>{
 if(id.startsWith('walk-'))return;
 await request(`/recommendations/${id}/feedback`,{method:'POST',body:JSON.stringify({completed:true,helpful,note:helpful?'도움이 됐어요':'다른 제안이 필요해요'})});
}

export async function clearWellnessData():Promise<void>{
 await request(await userPath('/users/me/data'),{method:'DELETE'});
}
export async function deleteAccountCompletely():Promise<void>{await request(await userPath('/users/me/account'),{method:'DELETE'})}

function localAssistantResponse(message:string):string{
 if(/죽|자해|사라지고|끝내고/.test(message))return'지금 혼자 버티지 않아도 괜찮아요. 즉시 위험하다면 119 또는 112에 연락하고, 자살예방상담전화 109에서 24시간 도움을 받을 수 있어요. 가능하면 지금 믿을 수 있는 사람에게도 곁에 있어 달라고 알려주세요.';
 if(/잠|수면|피곤/.test(message))return'지금은 서버의 최근 수면 흐름을 확인할 수 없어요. 우선 물 한 잔을 마시고 7분만 가볍게 움직인 뒤, 연결이 회복되면 실제 기록을 함께 살펴볼게요.';
 if(/집중|일|공부/.test(message))return'지금 상태에서는 긴 계획보다 짧은 시작이 좋아요. 할 일을 하나만 고르고 15분 집중한 뒤, 컨디션을 다시 확인해 볼까요?';
 if(/긴장|불안|스트레스/.test(message))return'긴장이 올라온 걸 알아차린 것만으로도 좋은 시작이에요. 어깨의 힘을 빼고 4초 들이마시고 6초 내쉬는 호흡을 세 번 해보세요.';
 return'지금 느끼는 상태를 한 단어로 기록해 볼까요? 최근 흐름과 함께 살펴보고, 부담 없이 바로 할 수 있는 행동 하나를 제안할게요.';
}
