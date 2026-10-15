import {studentSectionSyncSql} from './student-section-sync.js';
export function normalizeDateInput(value,label){
  const text=String(value??'').trim();
  if(!text)return null;
  if(/^\d{5}(\.\d+)?$/.test(text)){
    const date=new Date(Date.UTC(1899,11,30)+Number(text)*86400000);
    return date.toISOString().slice(0,10);
  }
  let match=text.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$/);
  if(match){
    const [,year,month,day]=match;
    const iso=`${year}-${month.padStart(2,'0')}-${day.padStart(2,'0')}`;
    if(!Number.isNaN(Date.parse(`${iso}T00:00:00Z`))&&new Date(`${iso}T00:00:00Z`).toISOString().slice(0,10)===iso)return iso;
  }
  match=text.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$/);
  if(match){
    const [,day,month,year]=match;
    const iso=`${year}-${month.padStart(2,'0')}-${day.padStart(2,'0')}`;
    if(!Number.isNaN(Date.parse(`${iso}T00:00:00Z`))&&new Date(`${iso}T00:00:00Z`).toISOString().slice(0,10)===iso)return iso;
  }
  throw new Error(`${label} "${text}" is invalid. Use YYYY-MM-DD or DD-MM-YYYY.`);
}

export async function insertStudent(client,data,userId){
  const admissionDate=normalizeDateInput(data.admissionDate,'Admission Date');
  const dateOfBirth=normalizeDateInput(data.dateOfBirth,'Date of Birth');
  const institutionId=(await client.query('SELECT institution_id FROM institutions WHERE is_active=TRUE ORDER BY institution_id LIMIT 1')).rows[0]?.institution_id;
  if(!institutionId)throw new Error('Create an active institution before adding students.');
  const academicYear=(await client.query('SELECT year_label,start_date FROM academic_years WHERE academic_year_id=$1',[Number(data.academicYearId)])).rows[0];
  const programme=(await client.query('SELECT programme_id,department_id,duration_years FROM programmes WHERE programme_id=$1 AND is_active=TRUE',[Number(data.programmeId)])).rows[0];
  if(!academicYear||!programme||Number(programme.department_id)!==Number(data.departmentId))throw new Error('Academic year, department, or programme is invalid.');
  const academicStartYear=academicYear.start_date instanceof Date?academicYear.start_date.getFullYear():Number(String(academicYear.start_date||'').slice(0,4));
  const admissionYear=academicStartYear||Number(String(admissionDate||'').slice(0,4));
  if(!admissionYear)throw new Error('The selected Academic Year has no valid start year.');
  let batchId=(await client.query('SELECT batch_id FROM admission_batches WHERE programme_id=$1 AND admission_year=$2 LIMIT 1',[programme.programme_id,admissionYear])).rows[0]?.batch_id;
  if(!batchId)batchId=(await client.query(`INSERT INTO admission_batches
    (programme_id,admission_year,batch_name,start_date,is_active) VALUES ($1,$2,$3,$4,TRUE)
    RETURNING batch_id`,[programme.programme_id,admissionYear,`${admissionYear}-${admissionYear+Math.ceil(Number(programme.duration_years)||3)}`,academicYear.start_date])).rows[0].batch_id;
  const id=Number((await client.query(`SELECT nextval(pg_get_serial_sequence('students','student_id')) AS id`)).rows[0].id);
  const serial=String(id).padStart(5,'0'),year=String(admissionYear);
  const registrationNumber=data.registrationNumber?.trim()||`REG-${year}-${serial}`;
  const rollNumber=data.rollNumber?.trim()||`ROLL-${year}-${serial}`;
  const studentCode=`STU-${year}-${serial}`;
  const nameParts=String(data.studentName||'').trim().split(/\s+/);const firstName=nameParts.shift();const lastName=nameParts.length?nameParts.pop():null;const middleName=nameParts.join(' ')||null;
  const activeStatus=(await client.query(`SELECT student_status_id FROM student_statuses WHERE institute_id=$1 AND status_code='ACTIVE' LIMIT 1`,[institutionId])).rows[0]?.student_status_id||null;
  await client.query(`INSERT INTO students
    (student_id,institution_id,institute_id,programme_id,batch_id,section_id,department_id,branch_id,
     academic_year_id,semester_id,admission_category_id,student_status_id,registration_no,roll_no,
     admission_no,registration_number,roll_number,admission_number,student_code,first_name,middle_name,
     last_name,gender,date_of_birth,category,blood_group,mobile,email,current_address,permanent_address,
     admission_date,admission_type,profile_photo_name,profile_photo_mime_type,profile_photo_size,
     status,is_active,is_deleted,created_by)
    VALUES ($1,$2,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$12,$13,$14,$15,$16,$17,$18,$19,$20,
      $21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,'ACTIVE',TRUE,FALSE,$32)`,
    [id,institutionId,programme.programme_id,batchId,data.sectionId?Number(data.sectionId):null,Number(data.departmentId),data.branchId?Number(data.branchId):null,
      Number(data.academicYearId),data.semesterId?Number(data.semesterId):null,data.admissionCategoryId?Number(data.admissionCategoryId):null,activeStatus,
      registrationNumber,rollNumber,data.admissionNumber.trim(),studentCode,firstName,middleName,lastName,data.gender||null,dateOfBirth,
      data.category||null,data.bloodGroup||null,data.mobile?.trim()||null,data.email?.trim()||null,data.presentAddress?.trim()||null,
      data.permanentAddress?.trim()||null,admissionDate,data.admissionType||null,data.photoName||null,data.photoMimeType||null,
      data.photoSize?Number(data.photoSize):null,userId]);
  await client.query(`INSERT INTO student_parents
    (student_id,father_name,mother_name,guardian_mobile) VALUES ($1,$2,$3,$4)`,
    [id,data.fatherName?.trim()||null,data.motherName?.trim()||null,data.guardianMobile?.trim()||null]);
  await client.query('UPDATE students SET student_profile_details=$1::jsonb WHERE student_id=$2',[JSON.stringify(data),id]);
  for(const [type,address] of [['Present',data.presentAddress],['Permanent',data.permanentAddress]])if(address?.trim())await client.query(`INSERT INTO student_addresses
    (student_id,address_type,address_line1) VALUES ($1,$2,$3)`,[id,type,address.trim()]);
  await client.query(studentSectionSyncSql);
  return {id,registrationNumber,rollNumber,studentCode};
}

