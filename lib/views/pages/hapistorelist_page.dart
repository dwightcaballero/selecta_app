import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/forms.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/pages/hapistore_page.dart';
import 'package:flutter_app/views/widgets/container_widget.dart';

class HapiStoreListPage extends StatefulWidget {
  const HapiStoreListPage({super.key});

  @override
  State<HapiStoreListPage> createState() => _HapiStoreListPageState();
}

class _HapiStoreListPageState extends State<HapiStoreListPage> {
  final HapiStoreService db = HapiStoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Timer? _debounceTimer;
  bool _isDealer = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: KForms.appbar('List of Hapi Stores'),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [_searchBar(), _hapiStoreListView()],
          ),
        ),
      ),
      floatingActionButton: _isDealer ? floatingAddButton() : null,
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by Store Name...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.0)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = "";
                    });
                  },
                )
              : null,
        ),
        onChanged: (value) {
          setState(() {
            _onSearchChanged(value);
          });
        },
      ),
    );
  }

  Widget _hapiStoreListView() {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.80,
      width: MediaQuery.sizeOf(context).width,

      child: StreamBuilder(
        stream: db.getListHapiStoreSearch(_searchQuery),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Text("Loading..."));
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No results found"));
          }

          List listHapiStore = snapshot.data?.docs;

          return ListView.builder(
            padding: EdgeInsets.only(bottom: 80),
            itemCount: listHapiStore.length,
            itemBuilder: (context, index) {
              Hapistore hapistore = listHapiStore[index].data();
              String hapistoreID = listHapiStore[index].id;

              return InkWell(
                onTap: () {
                  _isDealer
                      ? Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) {
                              return HapiStorePage(
                                hapiStoreID: hapistoreID,
                                hapistore: hapistore,
                              );
                            },
                          ),
                        )
                      : null;
                },
                child: ContainerWidget(
                  title: hapistore.storeName,
                  description1: hapistore.storeContact,
                  description2: hapistore.storeAddress,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget floatingAddButton() {
    return FloatingActionButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) {
              return HapiStorePage(
                hapiStoreID: '',
                hapistore: Hapistore.empty(),
              );
            },
          ),
        );
      },
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Icon(Icons.add, color: Colors.white),
    );
  }

  // Debounce prevents executing a Firestore query on every single keystroke
  void _onSearchChanged(String text) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = text.trim().toUpperCase();
      });
    });
  }

  void prefetchData() async {
    _isDealer = await KVariables.getIsDealer();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }
}
