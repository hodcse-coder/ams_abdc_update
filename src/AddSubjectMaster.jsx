import {Fragment,useEffect,useState} from 'react';
import * as XLSX from 'xlsx-js-style';
import './AddSubjectMaster.css';
import {parseSubjectSheet} from './subjectExcel.js';

const blank=()=>({programmeId:'',semesterId:'',code:'',name:'',theory:false,practical:false,theoryCredit:'',practicalCredit:'',isActive:true});
const semesterLabel=item=>item.name||`${item.semester_number} Semester`;
export default function AddSubjectMaster({initialProgramme='',initialSemester='',activeOnly=false}={}){
  const [data,setData]=useState({programmes:[],semesters:[],subjects:[]});
  const [form,setForm]=useState(blank),[editing,setEditing]=useState(null);
  const [showForm,setShowForm]=useState(false);
  const [importRows,setImportRows]=useState([]),[importFile,setImportFile]=useState('');
  const [page,setPage]=useState(1),[pageSize,setPageSize]=useState(10);
  const [filters,setFilters]=useState({programme:String(initialProgramme),semester:String(initialSemester),type:'',search:''});
  const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
  const headers=()=>({'Content-Type':'application/json',Authorization:`Bearer ${localStorage.getItem('abit_session')}`});
  async function request(path,options={}){
    const response=await fetch(path,{...options,headers:headers()});
    if(!response.headers.get('content-type')?.includes('application/json'))throw new Error('The application server is unavailable.');
    const body=await response.json();if(!response.ok||!body.ok)throw new Error(body.message||'Unable to complete this request.');return body;
  }
  async function load(){setLoading(true);try{setData(await request('/api/academic-subjects'));}catch(err){setError(err.message);}finally{setLoading(false);}}
  useEffect(()=>{load();},[]);
  useEffect(()=>{const hide=()=>setShowForm(false);hide();window.addEventListener('abit:hide-subject-form',hide);return()=>window.removeEventListener('abit:hide-subject-form',hide);},[]);
  const semesters=data.semesters.filter(item=>String(item.programme_id)===form.programmeId&&(item.is_active||String(item.id)===form.semesterId));
  const rows=data.subjects.flatMap(subject=>subject.components.map(component=>({...subject,...component}))).filter(row=>(!activeOnly||row.is_active)&&(!filters.programme||String(row.programme_id)===filters.programme)&&(!filters.semester||String(row.semester_id)===filters.semester)&&(!filters.type||row.type===filters.type)&&(!filters.search.trim()||`${row.code} ${row.name}`.toLowerCase().includes(filters.search.trim().toLowerCase()))).sort((a,b)=>a.programme_code.localeCompare(b.programme_code)||Number(a.semester_number)-Number(b.semester_number)||a.code.localeCompare(b.code));
  const semesterCounts=[...rows.reduce((groups,row)=>{const key=row.programme_id+':'+row.semester_id;if(!groups.has(key))groups.set(key,{programmeId:String(row.programme_id),semesterId:String(row.semester_id),label:row.programme_code+' ? '+(row.semester_name||'Semester '+row.semester_number),ids:new Set()});groups.get(key).ids.add(String(row.id));return groups;},new Map()).values()];
  const pageCount=Math.max(1,Math.ceil(rows.length/pageSize)),currentPage=Math.min(page,pageCount),start=(currentPage-1)*pageSize;
  const pageRows=rows.slice(start,start+pageSize);
  useEffect(()=>{setPage(1);},[filters.programme,filters.semester,filters.type,filters.search,pageSize]);
  function clear(){setForm(blank());setEditing(null);setImportRows([]);setImportFile('');setError('');setMessage('');}
  function downloadTemplate(){
    const programme=data.programmes.find(item=>item.is_active&&data.semesters.some(s=>s.is_active&&String(s.programme_id)===String(item.id)));
    const semester=data.semesters.find(item=>item.is_active&&String(item.programme_id)===String(programme?.id));
    const programmeCode=programme?.code||'BCA',semesterName=semester?semesterLabel(semester):'1ST';
    const sheet=XLSX.utils.aoa_to_sheet([['Programme','Semester','Subject Code','Subject Name','Theory Credit','Practical Credit','Status'],[programmeCode,semesterName,'SEC101','Problem Solving Techniques',3,'','Active'],[programmeCode,semesterName,'SEC102','Programming Lab','',2,'Active'],[programmeCode,semesterName,'SEC103','Database Management',3,1,'Active']]);
    sheet['!cols']=[{wch:18},{wch:18},{wch:18},{wch:38},{wch:18},{wch:20},{wch:14}];
    const book=XLSX.utils.book_new();XLSX.utils.book_append_sheet(book,sheet,'Subjects');XLSX.writeFile(book,'subject-upload-template.xlsx');
  }
  async function chooseExcel(event){
    const file=event.target.files?.[0];event.target.value='';if(!file)return;
    setError('');setMessage('');setImportRows([]);setImportFile('');
    try{
      if(file.size>10*1024*1024)throw new Error('Select a file smaller than 10 MB.');
      const book=XLSX.read(await file.arrayBuffer(),{type:'array'});
      const values=XLSX.utils.sheet_to_json(book.Sheets[book.SheetNames[0]],{header:1,defval:'',blankrows:false});
      const parsed=parseSubjectSheet(values,data);
      setImportRows(parsed);setImportFile(file.name);
    }catch(err){setError(err.message);}
  }
  async function importExcel(){
    setError('');setMessage('');
    if(!importRows.length){setError('Choose a valid Excel file before importing.');return;}
    setSaving(true);
    try{const body=await request('/api/academic-subjects/bulk',{method:'POST',body:JSON.stringify({rows:importRows})});clear();setShowForm(false);setMessage(body.message);await load();}catch(err){setError(err.message);}finally{setSaving(false);}
  }
  async function save(event){
    event.preventDefault();setError('');setMessage('');
    if(!form.theory&&!form.practical){setError('Select at least one subject type: Theory or Practical.');return;}
    const components=[];if(form.theory)components.push({type:'THEORY',credit:form.theoryCredit});if(form.practical)components.push({type:'PRACTICAL',credit:form.practicalCredit});
    if(components.some(c=>c.credit===''||!/^\d+(\.\d{1,2})?$/.test(String(c.credit))||Number(c.credit)>999.99)){setError('Enter a valid credit from 0 to 999.99 for each selected type.');return;}
    setSaving(true);
    try{const body=await request(editing?`/api/academic-subjects/${editing}`:'/api/academic-subjects',{method:editing?'PUT':'POST',body:JSON.stringify({programmeId:form.programmeId,semesterId:form.semesterId,code:form.code,name:form.name,isActive:form.isActive,components})});setForm(blank());setEditing(null);setShowForm(false);setMessage(body.message);await load();}catch(err){setError(err.message);}finally{setSaving(false);}
  }
  function edit(row){
    const subject=data.subjects.find(item=>item.id===row.id),theory=subject.components.find(c=>c.type==='THEORY'),practical=subject.components.find(c=>c.type==='PRACTICAL');
    setShowForm(true);setEditing(subject.id);setForm({programmeId:String(subject.programme_id),semesterId:String(subject.semester_id),code:subject.code,name:subject.name,isActive:subject.is_active,theory:!!theory,practical:!!practical,theoryCredit:theory?String(theory.credit):'',practicalCredit:practical?String(practical.credit):''});setMessage('');setError('');window.scrollTo({top:0,behavior:'smooth'});
  }
  async function remove(row){
    if(!window.confirm(`Delete ${row.code} — ${row.name} and all its Theory/Practical components?`))return;
    setError('');setMessage('');setSaving(true);
    try{const body=await request(`/api/academic-subjects/${row.id}`,{method:'DELETE'});if(String(editing)===String(row.id)){setForm(blank());setEditing(null);}setMessage(body.message);await load();}catch(err){setError(err.message);}finally{setSaving(false);}
  }
  const component=(type,label,creditField)=><div className={`subject-component-choice ${form[type]?'selected':''}`}><label><input type="checkbox" checked={form[type]} onChange={event=>setForm({...form,[type]:event.target.checked})}/><strong>{label}</strong></label>{form[type]?<label className="component-credit">{label} Credit *<input type="number" min="0" max="999.99" step="0.01" required value={form[creditField]} onChange={event=>setForm({...form,[creditField]:event.target.value})}/></label>:<span>Not selected</span>}</div>;
  return <div className="add-subject-master">
    <div className="subject-form-tabs" role="tablist" aria-label="Subject forms" onKeyDown={event=>{if(!["ArrowLeft","ArrowRight","Home","End"].includes(event.key))return;event.preventDefault();const next=event.key==="Home"?true:event.key==="End"?false:!showForm;setShowForm(next);document.getElementById(next?"add-subject-tab":"manage-subjects-tab")?.focus();}}><button type="button" role="tab" id="add-subject-tab" aria-selected={showForm} tabIndex={showForm?0:-1} aria-controls="add-subject-panel" onClick={()=>setShowForm(true)}>Add Subject</button><button type="button" role="tab" id="manage-subjects-tab" aria-selected={!showForm} tabIndex={showForm?-1:0} aria-controls="manage-subjects-panel" onClick={()=>setShowForm(false)}>Manage Subjects</button></div>
    {showForm&&<section className="subject-entry-card" id="add-subject-panel" role="tabpanel" aria-labelledby="add-subject-tab">
      <div className="subject-excel-upload"><div><strong>Excel Upload</strong><p>Programme and Semester are required in each Excel row. Use a programme code and its semester name or number.</p></div><button type="button" disabled={saving} onClick={downloadTemplate}>Download Template</button><label className="subject-file-button">Choose Excel File<input disabled={saving||loading} type="file" accept=".xlsx,.xls,.csv" onChange={chooseExcel}/></label></div>
      {importRows.length>0&&<div className="subject-import-preview"><span>{importFile} · {importRows.length} subjects ready</span><div className="subject-list-scroll"><table><thead><tr><th>Programme</th><th>Semester</th><th>Subject Code</th><th>Subject Name</th><th>Theory Credit</th><th>Practical Credit</th><th>Status</th></tr></thead><tbody>{importRows.slice(0,5).map(row=><tr key={`${row.programmeId}-${row.semesterId}-${row.code}`}><td>{row.programmeCode}</td><td>{row.semesterName}</td><td>{row.code}</td><td>{row.name}</td><td>{row.components.find(c=>c.type==='THEORY')?.credit??'—'}</td><td>{row.components.find(c=>c.type==='PRACTICAL')?.credit??'—'}</td><td>{row.isActive?'Active':'Inactive'}</td></tr>)}</tbody></table></div><div><button disabled={saving} onClick={()=>{setImportRows([]);setImportFile('');}}>Clear Upload</button><button className="subject-save" disabled={saving||loading} onClick={importExcel}>{saving?'Importing…':'Import Subjects'}</button></div></div>}
      <form onSubmit={save}><fieldset disabled={saving||loading}>
        <div className="subject-form-intro"><h4>{editing?'Edit Subject':'Add New Subject'}</h4><small>* Required fields</small></div>
        <div className="subject-entry-grid">
          <label>Programme *<select required value={form.programmeId} onChange={event=>setForm({...form,programmeId:event.target.value,semesterId:''})}><option value="">Select Programme</option>{data.programmes.filter(item=>item.is_active||String(item.id)===form.programmeId).map(item=><option key={item.id} value={item.id}>{item.code} — {item.name}</option>)}</select></label>
          <label>Semester *<select required disabled={!form.programmeId} value={form.semesterId} onChange={event=>setForm({...form,semesterId:event.target.value})}><option value="">Select Semester</option>{semesters.map(item=><option key={item.id} value={item.id}>{semesterLabel(item)}</option>)}</select></label>
          <label>Subject Code *<input required maxLength={30} value={form.code} onChange={event=>setForm({...form,code:event.target.value})}/></label>
          <label>Subject Name *<input required maxLength={200} value={form.name} onChange={event=>setForm({...form,name:event.target.value})}/></label>
        </div>
        <h4>Subject Type and Credit Details</h4><p className="subject-type-help">Select one or both subject types. Credits are entered separately. Theory and Practical may use the same code and name, together or in separate Excel rows.</p>
        <div className="subject-component-grid">{component('theory','Theory','theoryCredit')}{component('practical','Practical','practicalCredit')}</div>
        <fieldset className="subject-status"><legend>Status *</legend>{[true,false].map(active=><label key={String(active)}><input type="radio" name="subject-status" checked={form.isActive===active} onChange={()=>setForm({...form,isActive:active})}/>{active?'Active':'Inactive'}</label>)}</fieldset>
        <footer><button type="button" onClick={()=>{clear();setShowForm(false);}}>Cancel</button><button type="button" onClick={clear}>Clear</button><button className="subject-save" type="submit">{saving?'Saving…':editing?'Update Subject':'Save Subject'}</button></footer>
      </fieldset></form>
    </section>}
    {error&&<p className="subject-feedback error" role="alert">{error}</p>}{message&&<p className="subject-feedback success" role="status">{message}</p>}
    {!showForm&&<section className="subject-entry-card subject-results" id="manage-subjects-panel" role="tabpanel" aria-labelledby="manage-subjects-tab"><header><h3>Subject List</h3></header>
      <div className="subject-list-filters">
        <label>Programme<select value={filters.programme} onChange={event=>setFilters({...filters,programme:event.target.value,semester:''})}><option value="">All Programmes</option>{data.programmes.map(item=><option value={item.id} key={item.id}>{item.code}</option>)}</select></label>
        <label>Semester<select value={filters.semester} onChange={event=>setFilters({...filters,semester:event.target.value})}><option value="">All Semesters</option>{data.semesters.filter(item=>!filters.programme||String(item.programme_id)===filters.programme).map(item=><option value={item.id} key={item.id}>{!filters.programme?`${data.programmes.find(p=>String(p.id)===String(item.programme_id))?.code||''} — `:''}{semesterLabel(item)}</option>)}</select></label>
        <label>Type<select value={filters.type} onChange={event=>setFilters({...filters,type:event.target.value})}><option value="">All Types</option><option value="THEORY">Theory</option><option value="PRACTICAL">Practical</option></select></label>
        <label>Search<input placeholder="Subject Code / Name" value={filters.search} onChange={event=>setFilters({...filters,search:event.target.value})}/></label>
      </div>
      <div className="subject-list-scroll"><table><thead><tr>{['Sl.','Programme','Semester','Subject Code','Subject Name','Type','Credit','Status','Action'].map(label=><th key={label}>{label}</th>)}</tr></thead><tbody>
        {loading?<tr><td colSpan={9}>Loading subjects…</td></tr>:rows.length?pageRows.map((row,index)=><Fragment key={`${row.id}-${row.type}`}>{(index===0||String(pageRows[index-1].semester_id)!==String(row.semester_id)||String(pageRows[index-1].programme_id)!==String(row.programme_id))&&<tr className="subject-semester-group"><td colSpan={9}>{row.programme_code} ? {row.semester_name||'Semester '+row.semester_number} ? {semesterCounts.find(group=>group.programmeId===String(row.programme_id)&&group.semesterId===String(row.semester_id))?.ids.size} Subjects</td></tr>}<tr><td>{start+index+1}</td><td>{row.programme_code}</td><td>{row.semester_name||row.semester_number}</td><td>{row.code}</td><td>{row.name}</td><td><span className={`subject-type-badge ${row.type.toLowerCase()}`}>{row.type}</span></td><td>{Number(row.credit)}</td><td><span className={`subject-status-badge ${row.is_active?'active':'inactive'}`}>{row.is_active?'Active':'Inactive'}</span></td><td><div className="subject-row-actions"><button disabled={saving} onClick={()=>edit(row)}>Edit</button><button disabled={saving} className="delete" onClick={()=>remove(row)}>Delete</button></div></td></tr></Fragment>):<tr><td colSpan={9}>No subjects found.</td></tr>}
      </tbody></table></div><footer><div className="subject-pagination"><label>Rows per page<select value={pageSize} onChange={event=>setPageSize(Number(event.target.value))}>{[10,25,50].map(size=><option key={size} value={size}>{size}</option>)}</select></label><nav aria-label="Subject list pages"><button disabled={loading||currentPage===1} onClick={()=>setPage(currentPage-1)}>Previous</button><span aria-live="polite">Page {currentPage} of {pageCount}</span><button disabled={loading||currentPage===pageCount} onClick={()=>setPage(currentPage+1)}>Next</button></nav></div></footer>
    </section>}
  </div>;
}
