import { readFile } from 'node:fs/promises';

export const startupMigrations = [
  'subject_masters.sql', 'course-management.sql', 'batch-management.sql',
  'section-assignment.sql', 'section-definitions.sql', 'section-masters.sql',
  'employee-edit.sql', 'student-batch-labels.sql', 'mentoring-redesign.sql',
  'student-section-sync.sql', 'semester-promotion.sql', 'defined-semester-sections.sql',
  'class-teacher-subjects.sql', 'counselling-purposes.sql'
];

export function sourceScript(master, path) {
  const marker = `/* ABDC_SOURCE_BEGIN ${path} SHA256 `;
  const start = master.indexOf(marker);
  if (start === -1) throw new Error(`Missing master SQL source: ${path}`);
  const bodyStart = master.indexOf('\n', start) + 1;
  const end = master.indexOf(`\nABDC_SOURCE_END ${path} */`, bodyStart);
  if (end === -1) throw new Error(`Incomplete master SQL source: ${path}`);
  return master.slice(bodyStart, end);
}

export async function applyMasterMigrations(pool) {
  const master = await readFile(new URL('../ABDC_ERP.sql', import.meta.url), 'utf8');
  for (const name of startupMigrations) await pool.query(sourceScript(master, `server/${name}`));
}
