export type TimelineKind='sleep'|'checkin'|'recovery'|'activity'|'insight';

export type TimelineItem={
 id:string;
 time:string;
 title:string;
 detail:string;
 kind:TimelineKind;
 userConfirmed:boolean;
};

export type Recommendation={id:string;title:string;rationale:string};

export type Dashboard={
 wellnessLoad:string;
 score:number;
 metrics:{sleepMinutes:number;restingHeartRate:number;hrv:number;steps:number};
 timeline:TimelineItem[];
 recommendation:Recommendation|null;
 disclaimer:string;
};

export type WeeklyReport={
 totalCheckIns:number;
 topStatus:string|null;
 topCause:string|null;
 improvementRate:number;
 patterns:string[];
 insights:string;
};

export type CheckInStatus='OK'|'TENSE'|'TIRED'|'LOW_FOCUS'|'UNCOMFORTABLE';
export type CheckInCause='SLEEP'|'WORK'|'STUDY'|'RELATIONSHIP'|'PHYSICAL'|'UNKNOWN';

export type CheckInInput={
 userId:string;
 status:CheckInStatus;
 cause:CheckInCause;
 note:string;
 source:'WEB';
 recordedAt:string;
};

export type ConnectionMode='live'|'demo';
