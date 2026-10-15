export const studentImportColumns=['Admission No','Programme','Academic year','Student name','Admission Date'];
export function studentImportDate(value,date1904=false){
  if(typeof value==='number'&&Number.isFinite(value))value=new Date(Date.UTC(date1904?1904:1899,date1904?0:11,date1904?1:30)+Math.floor(value)*86400000).toISOString().slice(0,10);
  const text=String(value??'').trim();let iso;
  let match=text.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$/);
  if(match)iso=match[1]+'-'+match[2].padStart(2,'0')+'-'+match[3].padStart(2,'0');
  else{match=text.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$/);if(match)iso=match[3]+'-'+match[2].padStart(2,'0')+'-'+match[1].padStart(2,'0');}
  if(!iso||Number.isNaN(Date.parse(iso))||new Date(iso).toISOString().slice(0,10)!==iso)throw new Error('Admission Date must be a valid DD-MM-YYYY or YYYY-MM-DD date.');return iso;
}
export function validateStudentImportRows(rows){
  if(!Array.isArray(rows)||!rows.length||rows.length>500)throw new Error('Upload between 1 and 500 students.');
  const numbers=new Set();
  return rows.map((row,index)=>{
    try{
      const admissionNumber=String(row.admissionNumber??'').trim(),programme=String(row.programme??'').trim(),academicYear=String(row.academicYear??'').trim(),studentName=String(row.studentName??'').trim();
      if(!programme)throw new Error('Programme is required.');
      if(!academicYear)throw new Error('Academic year is required.');
      if(!admissionNumber||admissionNumber.length>50||!programme||!academicYear||!studentName)throw new Error('All five columns are required.');
      const parts=studentName.split(/\s+/);if(parts[0].length>80||(parts.length>1&&parts.at(-1).length>80)||(parts.length>2&&parts.slice(1,-1).join(' ').length>80))throw new Error('Student name is too long.');
      if(numbers.has(admissionNumber.toUpperCase()))throw new Error('Admission No is repeated in the file.');numbers.add(admissionNumber.toUpperCase());
      return {admissionNumber,programme,academicYear,studentName,admissionDate:studentImportDate(row.admissionDate)};
    }catch(error){throw new Error(`Row ${index+2}: ${error.message}`);}
  });
}
export function resolveStudentImportMasters(rows,{programmes,academicYears}){
  const normalize=value=>String(value??'').trim().toLowerCase().replace(/[\u2013\u2014]/g,'-').replace(/\s+/g,' ').replace(/\s*-\s*/g,'-');
  return rows.map((row,index)=>{
    const matches=programmes.filter(p=>p.is_active!==false&&[p.code,p.name].some(value=>normalize(value)===normalize(row.programme)));
    if(matches.length!==1)throw new Error(`Row ${index+2}: Programme "${row.programme}" must match one active programme code or name.`);
    const programme=matches[0];if(!programme.department_id)throw new Error(`Row ${index+2}: configure the Programme's Department first.`);
    const years=academicYears.filter(year=>{
      if(year.is_active===false)return false;
      const start=String(year.start_date||'').slice(0,4),end=String(year.end_date||'').slice(0,4);
      const aliases=[year.code,year.name];
      if(/^\d{4}$/.test(start)&&/^\d{4}$/.test(end))aliases.push(start+'-'+end,start+'-'+end.slice(-2));
      return aliases.some(value=>value&&normalize(value)===normalize(row.academicYear));
    });
    if(years.length!==1)throw new Error(`Row ${index+2}: Academic year "${row.academicYear}" must match one configured active year.`);
    return {...row,programme:programme.code,academicYear:years[0].code,departmentId:programme.department_id,programmeId:programme.id,academicYearId:years[0].id};
  });
}
export function parseStudentImportSheet(values,{date1904=false}={}){
  const normalize=value=>String(value??'').trim().toLowerCase().replace(/\s+/g,' ');
  const header=(values[0]||[]).map(normalize),indexes=studentImportColumns.map(column=>header.indexOf(normalize(column)));
  if(indexes.some(index=>index<0))throw new Error('Required columns: '+studentImportColumns.join(', ')+'.');
  return validateStudentImportRows(values.slice(1).map((row,index)=>{const values=indexes.map(column=>row[column]??'');try{return {admissionNumber:values[0],programme:values[1],academicYear:values[2],studentName:values[3],admissionDate:studentImportDate(values[4],date1904)};}catch(error){throw new Error(`Row ${index+2}: ${error.message}`);}}));
}
