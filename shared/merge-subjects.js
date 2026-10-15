// Combine separately entered Theory and Practical rows without merging distinct subjects.
export function mergeSubjectRows(rows){
  const subjects=new Map();
  rows.forEach((row,index)=>{
    const key=`${row.programmeId}:${row.semesterId}:${row.code}`;
    const previous=subjects.get(key);
    if(!previous){subjects.set(key,{...row,components:[...row.components]});return;}
    if(previous.name.toLowerCase()!==row.name.toLowerCase()||previous.isActive!==row.isActive)
      throw new Error(`Row ${index+2}: ${row.code} must have the same Subject Name and Status for Theory and Practical.`);
    for(const component of row.components){
      if(previous.components.some(item=>item.type===component.type))
        throw new Error(`Row ${index+2}: ${component.type} is repeated for ${row.code} in the same Programme and Semester.`);
      previous.components.push(component);
    }
  });
  return [...subjects.values()];
}
