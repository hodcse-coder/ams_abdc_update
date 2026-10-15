export function mentoringToday(date=new Date()){
 const parts=new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date);
 const value=type=>parts.find(part=>part.type===type).value;
 return `${value('year')}-${value('month')}-${value('day')}`;
}

export function formatMentoringDate(value){
 if(!value)return '?';
 const date=new Date(value);if(Number.isNaN(date.getTime()))return '?';
 return new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Kolkata',day:'2-digit',month:'2-digit',year:'numeric'}).format(date).replaceAll('/','-');
}
