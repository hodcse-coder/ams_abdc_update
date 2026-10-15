import {mergeSubjectRows} from '../shared/merge-subjects.js';
const semesterLabel=item=>item.name||`${item.semester_number} Semester`;
export function parseSubjectSheet(values,data){
      const columns=['Programme','Semester','Subject Code','Subject Name','Theory Credit','Practical Credit','Status'];
      const header=values.shift()?.map(value=>String(value).trim().toLowerCase())||[];
      const indexes=columns.map(column=>header.indexOf(column.toLowerCase()));
      if(indexes.some(index=>index<0))throw new Error('Use the template columns: '+columns.join(', ')+'.');
      if(!values.length||values.length>500)throw new Error('Upload between 1 and 500 subjects.');
      const parsed=values.map((row,index)=>{
        const [programmeText,semesterText,code,name,theory,practical,status]=indexes.map(column=>String(row[column]??'').trim());
        if(!programmeText||!semesterText)throw new Error(`Row ${index+2}: Programme and Semester are required.`);
        const matches=data.programmes.filter(p=>p.is_active&&[p.code,p.name].some(value=>String(value).trim().toLowerCase()===programmeText.toLowerCase()));
        if(matches.length!==1)throw new Error(`Row ${index+2}: Programme must match one active programme code or name.`);
        const programme=matches[0];
        const semesterMatches=data.semesters.filter(s=>s.is_active&&String(s.programme_id)===String(programme.id)&&[s.name,String(s.semester_number),`${s.semester_number}${s.semester_number===1?'ST':s.semester_number===2?'ND':s.semester_number===3?'RD':'TH'}`].some(value=>String(value||'').trim().toLowerCase()===semesterText.toLowerCase()));
        if(semesterMatches.length!==1)throw new Error(`Row ${index+2}: Semester must belong to ${programme.code}. Use its exact name or number.`);
        const semester=semesterMatches[0];
        if(!code||code.length>30||!name||name.length>200)throw new Error(`Row ${index+2}: enter a valid Subject Code and Name.`);
        if(!['active','inactive'].includes(status.toLowerCase()))throw new Error(`Row ${index+2}: Status must be Active or Inactive.`);
        const components=[];
        for(const [type,credit] of [['THEORY',theory],['PRACTICAL',practical]])if(credit!==''){
          if(!/^\d+(\.\d{1,2})?$/.test(credit)||Number(credit)>999.99)throw new Error(`Row ${index+2}: ${type} Credit must be between 0 and 999.99.`);
          components.push({type,credit:Number(credit)});
        }
        if(!components.length)throw new Error(`Row ${index+2}: enter at least one Theory or Practical credit.`);
        return {programmeId:programme.id,semesterId:semester.id,programmeCode:programme.code,semesterName:semesterLabel(semester),code:code.toUpperCase(),name,components,isActive:status.toLowerCase()==='active'};
      });
  return mergeSubjectRows(parsed);
}
