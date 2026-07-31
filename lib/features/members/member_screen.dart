import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../services/member_service.dart';

import '../../screens/add_member_screen.dart';

import 'member_body.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() =>
      _MembersScreenState();
}

class _MembersScreenState
    extends State<MembersScreen> {

  bool isLoading = true;

  List<Member> members = [];

  /// Tracks whether ANY mutation (add/edit/delete) happened while this
  /// screen was open, regardless of how the user navigates back (app bar
  /// back button, system back gesture, or hardware back button). Reported
  /// to the caller (Dashboard) via Navigator.pop's result.
  ///
  /// Why PopScope with canPop:false rather than just wiring a custom
  /// back button: the system back gesture and hardware back button don't
  /// go through a widget we control, so the only way to attach a result
  /// to *every* pop path is to intercept the pop itself and call
  /// Navigator.pop(context, true) ourselves. When nothing changed we let
  /// the default pop proceed with no result (equivalent to `false`, per
  /// the navigation contract — callers must treat absence of `true` as
  /// "nothing changed").
  bool _dataChanged = false;

  @override
  void initState() {
    super.initState();
    loadMembers();
  }

  Future<void> loadMembers() async {
    try {
      final data =
      await MemberService().getMembers();

      if (!mounted) return;

      setState(() {
        members = data;
        isLoading = false;
      });

    } catch (e) {

      debugPrint(
        "LOAD MEMBERS ERROR : $e",
      );

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> addMember() async {

    final result = await showAddMemberDialog(context);

    if (result == true) {
      _dataChanged = true;
      await loadMembers();
    }
  }

  @override
  Widget build(BuildContext context) {

    return PopScope(
      // Block the default pop ONLY once data has changed — that's the one
      // case where we need to supply a non-default result. Before any
      // change, canPop:true lets every back path behave exactly as before.
      canPop: !_dataChanged,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return; // pop already completed normally — nothing to do
        // canPop was false, meaning _dataChanged is true: finish the pop
        // ourselves, carrying the result the caller is awaiting.
        Navigator.pop(context, true);
      },
      child: Scaffold(

        appBar: AppBar(
          title: const Text(
            "Members",
          ),
        ),

        floatingActionButton:
        FloatingActionButton.extended(
          onPressed: addMember,
          icon: const Icon(Icons.add),
          label: const Text("Add Member"),
        ),

        body: Padding(
          padding: const EdgeInsets.all(16),
          child: MemberBody(
            members: members,
            isLoading: isLoading,
            onRefresh: loadMembers,
            onMemberChanged: () => _dataChanged = true,
          ),
        ),
      ),
    );
  }
}