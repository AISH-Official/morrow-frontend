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
 hasHealthData:boolean;
 scoreConfidence:'NONE'|'CHECKIN_ONLY'|'LOW'|'MEDIUM'|'HIGH';
 scoreReasons:string[];
 lastUpdatedAt:string|null;
 metrics:{sleepMinutes:number;restingHeartRate:number;hrv:number;steps:number;activeEnergyKcal:number;exerciseMinutes:number};
 healthDetails:{sleep:SleepDetail|null;workouts:WorkoutDetail[]};
 timeline:TimelineItem[];
 recommendation:Recommendation|null;
 disclaimer:string;
};

export type WeeklyReport={
 totalCheckIns:number;
 topStatus:string|null;
 topCause:string|null;
 improvementRate:number;
 changeFromPrevious:number;
 dailyScores:{date:string;score:number|null;checkInCount:number}[];
 patterns:string[];
 insights:string;
 suggestedRecoveryCount:number;
 completedRecoveryCount:number;
 recoveryHelpfulRate:number;
 topHelpfulAction:string|null;
 recoveryInsight:string;
};

export type CheckInStatus='OK'|'TENSE'|'TIRED'|'LOW_FOCUS'|'UNCOMFORTABLE';
export type CheckInCause='SLEEP'|'WORK'|'STUDY'|'RELATIONSHIP'|'PHYSICAL'|'UNKNOWN';

export type CheckInInput={
 userId:string;
 clientEventId:string;
 status:CheckInStatus;
 cause:CheckInCause;
 note:string;
 source:'WEB';
 recordedAt:string;
};

export type SleepDetail={clientSleepId:string;startAt:string;endAt:string;totalMinutes:number;coreMinutes:number;deepMinutes:number;remMinutes:number;awakeMinutes:number;source:string};
export type WorkoutDetail={clientWorkoutId:string;activityType:string;startAt:string;endAt:string;durationMinutes:number;activeEnergyKcal:number;distanceMeters:number;averageHeartRate:number;maxHeartRate:number;intensity:'LIGHT'|'MODERATE'|'HIGH';source:string};

export type ConnectionMode='live'|'offline';

export type PersonalizationProfile={
 userId:string;
 activeMemoryCount:number;
 evidenceCount:number;
 helpfulStrategyCount:number;
 avoidStrategyCount:number;
 lastLearnedAt:string|null;
 personalized:boolean;
};

export type UserMemory={
 id:string;
 type:'TRIGGER_PATTERN'|'RECOVERY_STRATEGY'|'PREFERENCE'|'GOAL';
 summary:string;
 positiveEvidence:number;
 negativeEvidence:number;
 evidenceCount:number;
 confidence:number;
 source:string;
 updatedAt:string;
};

export type AssistantResult={content:string;aiMode:'LIVE'|'FALLBACK'|'LOCAL';personalizationEvidenceCount:number;personalized:boolean};
