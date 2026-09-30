import { readFileSync } from 'node:fs';
import { before, after, test } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDoc, serverTimestamp, writeBatch, Timestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-buildtrack', firestore: {rules: readFileSync('../../firestore.rules', 'utf8')}, storage: {rules: readFileSync('../../storage.rules', 'utf8')}});
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    for (const role of ['admin', 'ceo', 'manager', 'supervisor', 'outsider']) {
      await setDoc(doc(db, 'users', role), {role: role === 'outsider' ? 'manager' : role, active: true});
    }
    await setDoc(doc(db, 'config/projectStatuses'), {items: [{id:'ongoing', stage:'ongoing', archived:false}, {id:'completed', stage:'completed', archived:false}]});
    await setDoc(doc(db, 'config/company'), {utcOffsetMinutes: 330, dprBackdateDays: 7});
    for (const id of ['open', 'closed']) {
      await setDoc(doc(db, 'projects', id), {name: 'Site', memberIds:['manager','supervisor'], managerId:'manager', deleted:false,
        statusId:id === 'open' ? 'ongoing' : 'completed', stage:id === 'open' ? 'ongoing' : 'completed',
        createdBy:'admin', createdAt: new Date(), updatedBy:'admin', updatedAt:new Date(), revision:0});
    }
  });
});
after(async () => { await env?.cleanup(); });
const db = role => env.authenticatedContext(role).firestore();
const stamp = role => ({createdBy:role, updatedBy:role, createdAt:serverTimestamp(), updatedAt:serverTimestamp(), deleted:false, revision:1});
const phase = role => ({...stamp(role), name:'Foundation', weight:20, actualPct:10, order:0, plannedStart:'2026-09-01', plannedEnd:'2026-09-20'});
test('CEO reads all projects but cannot modify phases', async () => {
  await assertSucceeds(getDoc(doc(db('ceo'), 'projects/open')));
  await assertFails(setDoc(doc(db('ceo'), 'projects/open/phases/ceo'), phase('ceo')));
});
test('assigned manager writes a validated phase; outsider cannot read or write', async () => {
  await assertSucceeds(setDoc(doc(db('manager'), 'projects/open/phases/manager'), phase('manager')));
  await assertFails(getDoc(doc(db('outsider'), 'projects/open')));
  await assertFails(setDoc(doc(db('outsider'), 'projects/open/phases/outsider'), phase('outsider')));
});
test('supervisor cannot change phase progress', async () => {
  await assertFails(setDoc(doc(db('supervisor'), 'projects/open/phases/supervisor'), phase('supervisor')));
});
test('invalid progress and zero weights are refused', async () => {
  await assertFails(setDoc(doc(db('manager'), 'projects/open/phases/bad'), {...phase('manager'), actualPct:101}));
  await assertFails(setDoc(doc(db('manager'), 'projects/open/phases/bad'), {...phase('manager'), weight:0}));
});
test('completed projects reject operational writes including admin', async () => {
  for (const role of ['manager','admin']) await assertFails(setDoc(doc(db(role), 'projects/closed/phases/new'), phase(role)));
});
test('manager cannot edit membership, status or derived money', async () => {
  for (const change of [{memberIds:['manager','outsider']}, {statusId:'completed'}, {spentTotalPaise:100}]) {
    await assertFails(updateDoc(doc(db('manager'),'projects/open'), {...change, updatedBy:'manager', updatedAt:serverTimestamp()}));
  }
});
test('supervisor may raise an assigned issue', async () => {
  await assertSucceeds(setDoc(doc(db('supervisor'), 'projects/open/issues/site'), {
    ...stamp('supervisor'), title:'Water supply', description:'Awaiting tanker', priorityId:'high', status:'open', assigneeId:'manager'}));
});
test('immutable history and unsupported project collections are protected', async () => {
  await assertFails(setDoc(doc(db('manager'), 'projects/open/expenses/unapproved'), {...stamp('manager'), amountPaise:100}));
  await assertFails(setDoc(doc(db('manager'), 'projects/open/phases/manager/revisions/forged'), {savedBy:'manager', savedAt:serverTimestamp(), name:'Forged'}));
});
test('office creates a project and template phases in one batch', async () => {
  const store = db('admin');
  const batch = writeBatch(store);
  batch.set(doc(store, 'projects/new'), {...stamp('admin'), name:'New site', memberIds:['manager'], statusId:'ongoing', stage:'ongoing', statusIndex:0});
  batch.set(doc(store, 'projects/new/phases/template'), {...stamp('admin'), name:'Seeded', weight:10, actualPct:0, order:0});
  await assertSucceeds(batch.commit());
});
test('a phase update and its old version can be saved atomically', async () => {
  const store = db('manager');
  const source = doc(store, 'projects/open/phases/manager');
  const before = (await getDoc(source)).data();
  const batch = writeBatch(store);
  batch.set(doc(store, 'projects/open/phases/manager/revisions/old'), {...before, savedAt:serverTimestamp(), savedBy:'manager'});
  batch.update(source, {actualPct:30, revision:2, updatedAt:serverTimestamp(), updatedBy:'manager'});
  batch.update(doc(store,'projects/open'), {updatedAt:serverTimestamp(), updatedBy:'manager'});
  await assertSucceeds(batch.commit());
});
test('daily report date, quantity, and submission identity are enforced', async () => {
  const date = new Date(Date.now() + 330 * 60000).toISOString().slice(0,10);
  const data = {...stamp('supervisor'), date, reportDay:Timestamp.fromDate(new Date(date + 'T00:00:00Z')),
    submittedAt:serverTimestamp(), submittedBy:'supervisor', targetQuantity:10, achievedQuantity:8,
    notes:'Poured concrete', unit:'m3', photoUrls:['projects/open/photo.jpg']};
  await assertSucceeds(setDoc(doc(db('supervisor'), 'projects/open/dprs', date), data));
  await assertFails(setDoc(doc(db('supervisor'), 'projects/open/dprs/wrong-id'), data));
  await assertFails(updateDoc(doc(db('supervisor'), 'projects/open/dprs', date), {achievedQuantity:-1, revision:2, updatedBy:'supervisor', updatedAt:serverTimestamp(), submittedAt:serverTimestamp()}));
});
test('storage accepts project uploads and refuses outsider and CEO writes', async () => {
  const bytes = new Uint8Array([1,2,3]);
  const path = 'projects/open/site.jpg';
  await assertSucceeds(uploadBytes(ref(env.authenticatedContext('manager').storage(),path),bytes,{contentType:'image/jpeg'}));
  await assertSucceeds(getBytes(ref(env.authenticatedContext('ceo').storage(),path)));
  await assertFails(getBytes(ref(env.authenticatedContext('outsider').storage(),path)));
  await assertFails(uploadBytes(ref(env.authenticatedContext('ceo').storage(),'projects/open/ceo.jpg'),bytes,{contentType:'image/jpeg'}));
  await assertFails(uploadBytes(ref(env.authenticatedContext('manager').storage(),'projects/closed/file.pdf'),bytes,{contentType:'application/pdf'}));
});
