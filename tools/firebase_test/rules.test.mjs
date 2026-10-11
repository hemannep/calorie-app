import { readFileSync } from 'node:fs';
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, serverTimestamp, writeBatch, updateDoc, collection, query, where, orderBy, limit, getDocs, onSnapshot } from 'firebase/firestore';
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

const codeFor = uid => 'K-' + Buffer.from(uid).toString('hex').toUpperCase().padEnd(24, '0').slice(0,24);
async function socialUser(uid) {
 const db=env.authenticatedContext(uid).firestore();const code=codeFor(uid);
 const batch=writeBatch(db);
 batch.set(doc(db,`socialUsers/${uid}`), {name:uid, inviteCode:code, joined:[], shareNutrition:false, shareActivity:false});
 batch.set(doc(db,`friendInvites/${code}`), {uid,name:uid});
 await assertSucceeds(batch.commit());return {db,uid,code};
}
function friendBatch(from,to,code=to.code) {
 const pair=[from.uid,to.uid].sort().join('_');const batch=writeBatch(from.db);
 batch.set(doc(from.db,`friendships/${pair}`), {members:[from.uid,to.uid],from:from.uid,to:to.uid,inviteCode:code,names:{[from.uid]:from.uid,[to.uid]:to.uid},createdAt:serverTimestamp()});
 batch.set(doc(from.db,`socialUsers/${from.uid}/friends/${to.uid}`),{pairId:pair});
 batch.set(doc(from.db,`socialUsers/${to.uid}/friends/${from.uid}`),{pairId:pair});
 return {batch,pair};
}
function message(uid,extra={}) {return {authorId:uid,authorName:uid,body:'Hello from another device',createdAt:serverTimestamp(),attachment:null,replyTo:null,...extra};}
function progress(uid,nutrition=false,activity=false) {return {name:uid,date:'2026-10-11',streak:3,days:Array.from({length:7},()=>({date:'2026-10-11',nutrition:nutrition?{calories:2000,protein:120,carbs:200,fat:60}:null,activity:activity?{minutes:30}:null})),updatedAt:serverTimestamp()};}
async function joinCircle(user,group='cal-2000') {
 const batch=writeBatch(user.db);
 batch.update(doc(user.db,`socialUsers/${user.uid}`),{joined:[group]});
 batch.set(doc(user.db,`communities/${group}/members/${user.uid}`),{name:user.uid,streak:3,updatedAt:serverTimestamp()});
 await assertSucceeds(batch.commit());
}
test('social identities are private and codes cannot be listed, stolen, or forged',async()=>{
 const a=await socialUser('identity-a');const b=await socialUser('identity-b');
 await assertFails(getDoc(doc(b.db,`socialUsers/${a.uid}`)));
 await assertFails(getDocs(collection(b.db,'friendInvites')));
 await assertSucceeds(getDoc(doc(b.db,`friendInvites/${a.code}`)));
 await assertFails(setDoc(doc(b.db,`friendInvites/${a.code}`),{uid:b.uid,name:b.uid}));
 await assertFails(setDoc(doc(b.db,`friendInvites/${codeFor('forged')}`),{uid:a.uid,name:a.uid}));
 await assertFails(setDoc(doc(b.db,`socialUsers/${a.uid}/friends/${b.uid}`),{pairId:'forged'}));
 const invalid=friendBatch(a,b,codeFor('absent'));await assertFails(invalid.batch.commit());
 await assertFails(setDoc(doc(a.db,'friendships/identity-a_identity-b'),{members:[a.uid,b.uid],from:a.uid,to:b.uid,inviteCode:b.code,names:{[a.uid]:a.uid,[b.uid]:b.uid},createdAt:serverTimestamp()}));
 const self=friendBatch(a,a,a.code);await assertFails(self.batch.commit());
});
test('valid invite enables mutual chat/progress; unfriend revokes both directions immediately',async()=>{
 const a=await socialUser('friend-a');const b=await socialUser('friend-b');const c=await socialUser('friend-c');
 await assertSucceeds(setDoc(doc(a.db,`socialProgress/${a.uid}`),progress(a.uid)));
 await assertFails(getDoc(doc(b.db,`socialProgress/${a.uid}`)));
 const {batch,pair}=friendBatch(a,b);await assertSucceeds(batch.commit());
 await assertSucceeds(getDoc(doc(b.db,`friendships/${pair}`)));
 await assertSucceeds(getDoc(doc(b.db,`socialProgress/${a.uid}`)));
 await assertFails(getDoc(doc(c.db,`socialProgress/${a.uid}`)));
 await assertFails(getDoc(doc(c.db,`friendships/${pair}`)));
 await assertSucceeds(getDocs(query(collection(b.db,'friendships'),where('members','array-contains',b.uid))));
 await assertFails(getDocs(collection(b.db,'friendships')));
 const ref=doc(a.db,`friendships/${pair}/messages/first`);
 await assertSucceeds(setDoc(ref,message(a.uid)));
 await assertSucceeds(getDoc(doc(b.db,ref.path)));
 await assertSucceeds(setDoc(doc(b.db,`friendships/${pair}/messages/second`),message(b.uid)));
 await assertFails(setDoc(doc(c.db,`friendships/${pair}/messages/intruder`),message(c.uid)));
 await assertFails(setDoc(doc(a.db,`friendships/${pair}/messages/forged`),message(b.uid)));
 await assertFails(updateDoc(doc(a.db,`friendships/${pair}`),{members:[a.uid,c.uid]}));
 await assertFails(deleteDoc(doc(a.db,`friendships/${pair}`)));
 const remove=writeBatch(b.db);remove.delete(doc(b.db,`friendships/${pair}`));remove.delete(doc(b.db,`socialUsers/${a.uid}/friends/${b.uid}`));remove.delete(doc(b.db,`socialUsers/${b.uid}/friends/${a.uid}`));await assertSucceeds(remove.commit());
 await assertFails(getDoc(doc(b.db,`socialProgress/${a.uid}`)));
 await assertFails(getDoc(doc(a.db,`socialProgress/${b.uid}`)));
 await assertFails(getDoc(doc(a.db,ref.path)));
 await assertFails(setDoc(doc(b.db,`friendships/${pair}/messages/after-removal`),message(b.uid)));
});
test('rotating an invite invalidates both its code and QR capability',async()=>{
 const a=await socialUser('rotate-a');const b=await socialUser('rotate-b');
 const next=codeFor('rotate-new');const rotate=writeBatch(b.db);
 rotate.update(doc(b.db,`socialUsers/${b.uid}`),{inviteCode:next});rotate.delete(doc(b.db,`friendInvites/${b.code}`));rotate.set(doc(b.db,`friendInvites/${next}`),{uid:b.uid,name:b.uid});await assertSucceeds(rotate.commit());
 await assertFails(friendBatch(a,b).batch.commit());
 await assertSucceeds(friendBatch(a,b,next).batch.commit());
});
test('progress sharing is opt-in, schema constrained, and can be cleared atomically',async()=>{
 const a=await socialUser('privacy-a');const b=await socialUser('privacy-b');await assertSucceeds(friendBatch(a,b).batch.commit());
 const ref=doc(a.db,`socialProgress/${a.uid}`);
 await assertFails(setDoc(ref,progress(a.uid,true,true)));
 const enable=writeBatch(a.db);enable.update(doc(a.db,`socialUsers/${a.uid}`),{shareNutrition:true,shareActivity:true});enable.set(ref,progress(a.uid,true,true));await assertSucceeds(enable.commit());
 assert.equal((await getDoc(doc(b.db,ref.path))).data().days[0].nutrition.calories,2000);
 await assertFails(setDoc(ref,{...progress(a.uid,true,true),weight:70}));
 await assertFails(setDoc(doc(b.db,ref.path),progress(a.uid)));
 const disable=writeBatch(a.db);disable.update(doc(a.db,`socialUsers/${a.uid}`),{shareNutrition:false,shareActivity:false});disable.set(ref,progress(a.uid));await assertSucceeds(disable.commit());
 const shared=(await getDoc(doc(b.db,ref.path))).data();assert.ok(shared.days.every(day=>day.nutrition===null&&day.activity===null));
});
test('communities require membership, support live replies/cheers/reports, and revoke access on leave',async()=>{
 const a=await socialUser('circle-a');const b=await socialUser('circle-b');const c=await socialUser('circle-c');
 await assertFails(setDoc(doc(a.db,'communities/unknown/members/circle-a'),{name:a.uid,streak:1,updatedAt:serverTimestamp()}));
 await assertFails(getDocs(collection(a.db,'communities/cal-2000/messages')));
 await joinCircle(a);await joinCircle(b);
 const messages=collection(b.db,'communities/cal-2000/messages');
 const received=new Promise((resolve,reject)=>{const timer=setTimeout(()=>{stop();reject(new Error('live listener timed out'));},8000);const stop=onSnapshot(query(messages,orderBy('createdAt','desc'),limit(100)),snapshot=>{if(snapshot.docs.some(doc=>doc.id==='live-message')){clearTimeout(timer);stop();resolve();}},reject);});
 const ref=doc(a.db,'communities/cal-2000/messages/live-message');await assertSucceeds(setDoc(ref,message(a.uid)));await received;
 await assertSucceeds(setDoc(doc(b.db,'communities/cal-2000/messages/reply'),message(b.uid,{replyTo:'live-message',attachment:{title:'Lunch',calories:500,protein:30,carbs:60,fat:15}})));
 await assertFails(setDoc(doc(c.db,'communities/cal-2000/messages/intruder'),message(c.uid)));
 await assertFails(setDoc(doc(a.db,'communities/cal-2000/messages/oversized'),message(a.uid,{body:'x'.repeat(2001)})));
 await assertFails(setDoc(doc(a.db,'communities/cal-2000/messages/photo-leak'),message(a.uid,{attachment:{title:'private',privateDiary:'data'}})));
 const cheer=doc(b.db,'communities/cal-2000/messages/live-message/cheers/circle-b');await assertSucceeds(setDoc(cheer,{createdAt:serverTimestamp()}));await assertSucceeds(deleteDoc(cheer));
 await assertFails(setDoc(doc(b.db,'communities/cal-2000/messages/live-message/cheers/circle-a'),{createdAt:serverTimestamp()}));
 await assertSucceeds(setDoc(doc(b.db,'socialReports/report-one'),{reporter:b.uid,room:'cal-2000',message:'live-message',group:true,reason:'Inappropriate or harmful content',createdAt:serverTimestamp()}));
 await assertFails(getDoc(doc(a.db,'socialReports/report-one')));
 await assertFails(deleteDoc(doc(b.db,ref.path)));
 await assertSucceeds(getDocs(query(collection(b.db,'communities/cal-2000/members'),orderBy('streak','desc'),limit(100))));
 const leave=writeBatch(b.db);leave.update(doc(b.db,`socialUsers/${b.uid}`),{joined:[]});leave.delete(doc(b.db,`communities/cal-2000/members/${b.uid}`));await assertSucceeds(leave.commit());
 await assertFails(getDoc(doc(b.db,ref.path)));
 await assertFails(setDoc(doc(b.db,'communities/cal-2000/messages/after-leave'),message(b.uid)));
 await assertSucceeds(deleteDoc(ref));
});
