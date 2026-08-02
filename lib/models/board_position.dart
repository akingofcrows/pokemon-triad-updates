class BoardPosition {
  const BoardPosition(this.row, this.column);

  final int row;
  final int column;

  bool get isValid => row >= 0 && row < 3 && column >= 0 && column < 3;

  int get index => row * 3 + column;

  static const _names = <int, String>{
    0: 'top left',
    1: 'top',
    2: 'top right',
    3: 'left',
    4: 'center',
    5: 'right',
    6: 'bottom left',
    7: 'bottom',
    8: 'bottom right',
  };

  String get positionName => _names[index] ?? 'tile ${index + 1}';

  factory BoardPosition.fromIndex(int index) {
    return BoardPosition(index ~/ 3, index % 3);
  }

  BoardPosition offset(int rowOffset, int columnOffset) {
    return BoardPosition(row + rowOffset, column + columnOffset);
  }

  @override
  bool operator ==(Object other) {
    return other is BoardPosition && other.row == row && other.column == column;
  }

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'BoardPosition($row, $column)';
}
