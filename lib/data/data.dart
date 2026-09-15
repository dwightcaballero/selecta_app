class KPlacement {
  String itemName;
  String itemCode;
  bool isPlaced;
  bool isPlacedFromDB;
  String itemImagePath;

  KPlacement({required this.itemName, required this.itemCode, required this.isPlaced, required this.isPlacedFromDB, required this.itemImagePath});
}

class KData {
  static List<KPlacement> getListPlacement() {
    return [
      KPlacement(
        itemName: "Watermelon Slice",
        itemCode: "cotc1",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/watermelon.png",
      ),
      KPlacement(
        itemName: "Chocky Stick",
        itemCode: "cotc2",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/chocky.png",
      ),
      KPlacement(
        itemName: "Avocado Choco",
        itemCode: "cotc3",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/avochoco.png",
      ),
      KPlacement(
        itemName: "Boom Boom Choco",
        itemCode: "cotc4",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/boom.png",
      ),
      KPlacement(
        itemName: "Cornetto Choco",
        itemCode: "cotc5",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/corchoco.png",
      ),
      KPlacement(
        itemName: "Cornetto Cookies & Dream",
        itemCode: "cotc6",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/corcnc.png",
      ),
      KPlacement(
        itemName: "Bday 3in1 C-K-U",
        itemCode: "cotc7",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/cku.png",
      ),
      KPlacement(
        itemName: "Bday 3in1 U-M-A",
        itemCode: "cotc8",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/uma.png",
      ),
      KPlacement(
        itemName: "Bday 3+1 C-K-U-M",
        itemCode: "cotc9",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/ckum.png",
      ),
      KPlacement(
        itemName: "Sup Double Dutch",
        itemCode: "cotc10",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/dd.png",
      ),
      KPlacement(
        itemName: "Sup Rocky Road",
        itemCode: "cotc11",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/rr.png",
      ),
      KPlacement(
        itemName: "Sup Cookies & Cream",
        itemCode: "cotc12",
        isPlaced: false,
        isPlacedFromDB: false,
        itemImagePath: "assets/images/placement/cnc.png",
      ),
    ];
  }
}
