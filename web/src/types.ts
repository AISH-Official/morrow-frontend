export type TimelineItem={id:string;time:string;title:string;detail:string;kind:'sleep'|'checkin'|'recovery';userConfirmed:boolean};
export type Dashboard={wellnessLoad:string;score:number;metrics:{sleepMinutes:number;restingHeartRate:number;hrv:number;steps:number};timeline:TimelineItem[];recommendation:{id:string;title:string;rationale:string};disclaimer:string};
