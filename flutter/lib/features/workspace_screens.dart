import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/store.dart';
import '../ui/gl.dart';
import 'chat_screens.dart';

part 'groups_screens.dart';
part 'project_screens.dart';
part 'task_screens.dart';

final _random = Random.secure();

List<JsonMap> _submissions(JsonMap task) =>
    (task['submissions'] as List? ?? []).whereType<JsonMap>().toList();

bool _member(GrouplyStore store, JsonMap? group) =>
    store.authenticated &&
    group != null &&
    group.ids('memberIDs').contains(store.currentUserID);

bool _coordinator(GrouplyStore store, JsonMap? group) =>
    _member(store, group) &&
    group!.text('coordinatorID') == store.currentUserID;

class GroupsScreen extends _WorkspaceScreen {
  const GroupsScreen({super.key, required super.store});
  @override
  State<GroupsScreen> createState() => _GroupsState();
}

class MyTasksScreen extends _WorkspaceScreen {
  const MyTasksScreen({super.key, required super.store});
  @override
  State<MyTasksScreen> createState() => _MyTasksState();
}

class GroupScreen extends _WorkspaceScreen {
  const GroupScreen({super.key, required super.store, required this.groupID});
  final String groupID;
  @override
  State<GroupScreen> createState() => _GroupState();
}

class ProjectScreen extends _WorkspaceScreen {
  const ProjectScreen({
    super.key,
    required super.store,
    required this.projectID,
  });
  final String projectID;
  @override
  State<ProjectScreen> createState() => _ProjectState();
}

class TaskScreen extends _WorkspaceScreen {
  const TaskScreen({super.key, required super.store, required this.taskID});
  final String taskID;
  @override
  State<TaskScreen> createState() => _TaskState();
}

abstract class _WorkspaceScreen extends StatefulWidget {
  const _WorkspaceScreen({super.key, required this.store});
  final GrouplyStore store;
}

abstract class _WorkspaceState<T extends _WorkspaceScreen> extends State<T> {
  bool busy = false;
  GrouplyStore get store => widget.store;

  void feedback(String message, {GLToastKind kind = GLToastKind.ok}) {
    if (!mounted) return;
    showGLToast(context, message, kind: kind);
  }

  Future<JsonMap?> mutate(
    String action,
    JsonMap payload, {
    bool inlineError = false,
  }) async {
    if (busy || store.loading) return null;
    setState(() => busy = true);
    try {
      final result = await store.mutate(action, payload);
      feedback('Perubahan tersimpan.');
      return result;
    } catch (error) {
      feedback(error.toString(), kind: GLToastKind.err);
      if (inlineError) rethrow;
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(
    String heading,
    String message, {
    String ok = 'Lanjutkan',
    bool destructive = false,
  }) => showGLConfirm(
    context,
    title: heading,
    text: message,
    ok: ok,
    destructive: destructive,
  );

  void open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}
