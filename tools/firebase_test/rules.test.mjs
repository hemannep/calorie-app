import { readFileSync } from 'node:fs';
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, connectAuthEmulator, createUserWithEmailAndPassword, signInWithEmailAndPassword, signOut } from 'firebase/auth';
let env;
const record = (extra = {}) => ({payload:'{"name":"Meal"}',deleted:false,updatedAt:serverTimestamp(),schemaVersion:1,...extra});
before(async()=> {env=await initializeTestEnvironment({projectId:'demo-kayleo',firestore:{rules:readFileSync('../../firestore.rules','utf8')}});});
after(async()=> {await env.cleanup();});
test('owner can save and restore, other accounts and guests cannot read or write',async()=>{
 const alice=env.authenticatedContext('alice').firestore();const bob=env.authenticatedContext('bob').firestore();const guest=env.unauthenticatedContext().firestore();
 await assertSucceeds(setDoc(doc(alice,'users/alice/kayleoRecords/meals:one'),record()));
 await assertSucceeds(getDoc(doc(alice,'users/alice/kayleoRecords/meals:one')));
 await assertFails(getDoc(doc(bob,'users/alice/kayleoRecords/meals:one')));
 await assertFails(setDoc(doc(bob,'users/alice/kayleoRecords/meals:two'),record()));
 await assertFails(getDoc(doc(guest,'users/alice/kayleoRecords/meals:one')));
 await assertFails(setDoc(doc(guest,'users/alice/kayleoRecords/meals:two'),record()));
});
test('schema and namespace reject unsafe records; tombstones remain readable',async()=>{
 const db=env.authenticatedContext('alice').firestore();const ref=doc(db,'users/alice/kayleoRecords/drinks:one');
 await assertFails(setDoc(ref,record({payload:3})));
 await assertFails(setDoc(ref,record({premium:true})));
 await assertFails(setDoc(ref,record({updatedAt:new Date(0)})));
 await assertFails(setDoc(ref,record({payload:'x'.repeat(450001)})));
 await assertFails(setDoc(doc(db,'users/alice/kayleoRecords/premium'),record()));
 await assertSucceeds(setDoc(ref,record({deleted:true,payload:''})));
 assert.equal((await getDoc(ref)).data().deleted,true);
 await assertFails(deleteDoc(ref));
 await assertFails(setDoc(doc(db,'users/alice'),{admin:true}));
});
test('real Auth registration verifies password, preserves UID and isolates another account',async()=>{
 const app=initializeApp({apiKey:'demo-key',projectId:'demo-kayleo'},'auth-test');const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
 try {
 const email=`owner-${Date.now()}@example.test`;const registered=await createUserWithEmailAndPassword(auth,email,'Test-pass-123');const uid=registered.user.uid;
 await signOut(auth);assert.equal(auth.currentUser,null);
 await assert.rejects(signInWithEmailAndPassword(auth,email,'wrong-password'));
 const signed=await signInWithEmailAndPassword(auth,email,'Test-pass-123');assert.equal(signed.user.uid,uid);
 await assert.rejects(createUserWithEmailAndPassword(auth,email,'Test-pass-123'));
 const other=await createUserWithEmailAndPassword(auth,`other-${Date.now()}@example.test`,'Test-pass-456');assert.notEqual(other.user.uid,uid);
 } finally {await deleteApp(app);}
});
