// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * An indexed sequence of elements of the same type.
 *
 * This is a primitive interface that any finite integer-indexable
 * sequence can implement.
 * It is intended for data structures where access by index is
 * the most efficient way to access the data.
 */
abstract class Sequence<T> {
  /**
   * The limit of valid indices of the sequence.
   *
   * The length getter should be efficient.
   */
  int get length;

  /**
   * Returns the value at the given [index].
   *
   * Valid indices must be in the range [:0..length - 1:].
   * The lookup operator should be efficient.
   */
  T operator[](int index);
}

/**
 * A skeleton class for a [Collection] that is also a [Sequence].
 */
abstract class SequenceCollection<E> implements Collection<E>, Sequence<E> {
  // The class is intended for use as a mixin as well.

  Iterator<E> iterator() => new SequenceIterator(sequence);

  void forEach(f(E element)) {
    for (int i = 0; i < this.length; i++) f(this[i]);
  }

  Collection map(f(E element)) {
    List result = new List();
    for (int i = 0; i < this.length; i++) {
      result.add(f(this[i]));
    }
    return result;
  }

  bool contains(E value) {
    for (int i = 0; i < sequence.length; i++) {
      if (sequence[i] == value) return true;
    }
    return false;
  }

  reduce(initialValue, combine(previousValue, E element)) {
    var value = initialValue;
    for (int i = 0; i < this.length; i++) {
      value = combine(value, this[i]);
    }
    return value;
  }

  Collection<E> filter(bool f(E element)) {
    List<E> result = <E>[];
    for (int i = 0; i < this.length; i++) {
      E element = this[i];
      if (f(element)) result.add(element);
    }
    return result;
  }

  bool every(bool f(E element)) {
    for (int i = 0; i < this.length; i++) {
      if (!f(this[i])) return false;
    }
    return true;
  }

  bool some(bool f(E element)) {
    for (int i = 0; i < this.length; i++) {
      if (f(this[i])) return true;
    }
    return false;
  }

  bool isEmpty() {
    return this.length == 0;
  }
}


/**
 * An unmodifiable [List] backed by a [Sequence].
 */
class SequenceList<E> extends SequenceCollection<E> implements List<E> {
  Sequence<E> sequence;
  SequenceList(this.sequence);

  int get length => sequence.length;

  T operator[](int index) => sequence[index];

  int indexOf(E value, [int start = 0]) {
    for (int i = start; i < sequence.length; i++) {
      if (sequence[i] == value) return i;
    }
    return -1;
  }

  int lastIndexOf(E value, [int start]) {
    if (start == null) start = sequence.length - 1;
    for (int i = start; i >= 0; i--) {
      if (sequence[i] == value) return i;
    }
    return -1;
  }

  E last() => sequence[sequence.length - 1];

  List<E> getRange(int start, int length) {
    List<E> result = <E>[];
    for (int i = 0; i < length; i++) {
      result.add(sequence[start + i]);
    }
    return result;
  }

  void operator []=(int index, E value) {
    throw new UnsupportedOperationException(
        "Cannot modify an unmodifiable list");
  }

  void set length(int newLength) {
    throw new UnsupportedOperationException(
        "Cannot change the length of an unmodifiable list");
  }

  void add(E value) {
    throw new UnsupportedOperationException(
        "Cannot add to an unmodifiable list");
  }

  void addLast(E value) {
    throw new UnsupportedOperationException(
        "Cannot add to an unmodifiable list");
  }

  void addAll(Collection<E> collection) {
    throw new UnsupportedOperationException(
        "Cannot add to an unmodifiable list");
  }

  void sort([Comparator<E> compare]) {
    throw new UnsupportedOperationException(
        "Cannot modify an unmodifiable list");
  }

  void clear() {
    throw new UnsupportedOperationException(
        "Cannot clear an unmodifiable list");
  }

  E removeAt(int index) {
    throw new UnsupportedOperationException(
        "Cannot remove in an unmodifiable list");
  }

  E removeLast() {
    throw new UnsupportedOperationException(
        "Cannot remove in an unmodifiable list");
  }

  void setRange(int start, int length, List<E> from, [int startFrom]) {
    throw new UnsupportedOperationException(
        "Cannot modify an unmodifiable list");
  }

  void removeRange(int start, int length) {
    throw new UnsupportedOperationException(
        "Cannot remove in an unmodifiable list");
  }

  void insertRange(int start, int length, [E initialValue]) {
    throw new UnsupportedOperationException(
        "Cannot insert range in an unmodifiable list");
  }
}

/**
 * Iterates over a [Sequence] in growing index order.
 */
class SequenceIterator<E> implements Iterator<E> {
  Sequence<E> _sequence;
  int _position;
  SequenceIterator(this._sequence) : _position = 0;
  bool hasNext() => _position < _sequence.length;
  E next() {
    if (hasNext()) return _sequence[_position++];
    throw new NoMoreElementsException();
  }
}

