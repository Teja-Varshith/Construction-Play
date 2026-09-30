import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chennapatanam/features/projects/data/project_detail_repository.dart';
import 'package:chennapatanam/features/projects/data/project_repository.dart';
import 'package:chennapatanam/features/projects/domain/project.dart';
import 'package:chennapatanam/core/utils/work_day.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ProjectDetailRepository repo;
  setUp(() async {
    db = FakeFirebaseFirestore(); repo = ProjectDetailRepository(db);
    await db.doc('projects/p').set({'name': 'Site', 'statusId': 'ongoing', 'deleted': false, 'revision': 0});
    await db.doc('config/projectStatuses').set({'items': [
      {'id': 'ongoing', 'stage': 'ongoing', 'label': 'Ongoing'},
      {'id': 'completed', 'stage': 'completed', 'label': 'Completed'},
    ]});
    await db.doc('config/company').set({'utcOffsetMinutes': 330, 'dprBackdateDays': 7});
  });
  test('daily reports use deterministic ids and reject accidental replacement', () async {
    final day = WorkDay.today();
    final data = {'date': day, 'notes': 'Foundation', 'targetQuantity': 10, 'achievedQuantity': 8};
    await repo.save('p', 'dprs', data, uid: 'manager', id: day);
    await expectLater(repo.save('p', 'dprs', data, uid: 'manager', id: day), throwsStateError);
    expect((await db.collection('projects/p/dprs').get()).docs.length, 1);
    await repo.save('p', 'dprs', {...data, 'notes': 'Corrected'}, uid: 'manager', id: day, expectedRevision: 1);
    expect((await db.collection('projects/p/dprs/$day/revisions').get()).docs.single.data()['notes'], 'Foundation');
    expect((await db.collection('activity').get()).docs.length, 2);
  });
  test('stale revision is rejected without modifying the record', () async {
    await repo.save('p', 'issues', {'title': 'Water'}, uid: 'manager', id: 'i');
    await expectLater(repo.save('p', 'issues', {'title': 'Lost edit'}, uid: 'manager', id: 'i', expectedRevision: 0), throwsStateError);
    expect((await db.doc('projects/p/issues/i').get()).data()!['title'], 'Water');
  });
  test('completed project rejects new operational records', () async {
    await db.doc('projects/p').update({'statusId': 'completed'});
    await expectLater(repo.save('p', 'issues', {'title': 'Water'}, uid: 'manager'), throwsStateError);
  });
  test('future daily report is rejected', () async {
    await expectLater(repo.save('p', 'dprs', {'date': '2099-01-01'}, uid: 'manager', id: '2099-01-01'), throwsStateError);
  });
  test('project details detect concurrent updates', () async {
    final projects = ProjectRepository(db);
    const before = Project(id: 'p', name: 'Site', statusId: 'ongoing');
    await projects.saveDetails(before, {'name': 'Latest'}, 'manager');
    await expectLater(projects.saveDetails(before, {'name': 'Old edit'}, 'manager'), throwsStateError);
    expect((await db.doc('projects/p').get()).data()!['name'], 'Latest');
  });
}
