// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

/**
 * @title RankedList
 * @dev Doubly linked list of ranked objects. The head will always have the highest rank and
 * elements will be ordered down towards the tail.
 */
library LibRankedList {

    //    event ObjectCreated(uint256 id, int256 rank, address data);
    //    event ObjectsLinked(uint256 prev, uint256 next);
    //    event ObjectRemoved(uint256 id);
    //    event NewHead(uint256 id);
    //    event NewTail(uint256 id);

    struct Object {
        uint256 id;
        uint256 next;
        uint256 prev;
        int256 rank;
        address data;
    }

    struct RankedList {
        uint256 head;
        uint256 tail;
        uint256 size;
        mapping(uint256 => Object) objects;
    }

    function getByAddress(RankedList storage self, address _data)
    internal
    view
    returns (uint256, uint256, uint256, int256, address)
    {
        return get(self, uint256(uint160(_data)));
    }

    /**
     * @dev Retrieves the Object denoted by `_id`.
     */
    function get(RankedList storage self, uint256 _id)
    internal
    view
    returns (uint256, uint256, uint256, int256, address)
    {
        Object memory object = self.objects[_id];
        return (object.id, object.next, object.prev, object.rank, object.data);
    }

    /**
     * @dev Return the id of the first Object with a lower or equal rank, starting from the head.
     */
    function findRank(RankedList storage self, int256 _rank)
    internal
    view
    returns (uint256)
    {
        Object memory object = self.objects[self.head];
        while (object.id != 0 && object.rank > _rank) {
            object = self.objects[object.next];
        }
        return object.id;
    }

    function updateRank(RankedList storage self, address _data, int256 _rank)
    internal
    {
        uint256 id = uint256(uint160(_data));
        Object memory object = self.objects[id];
        bool needMove = false;
        if (object.next != 0) {
            Object memory next = self.objects[object.next];
            if (next.rank > _rank) {
                needMove = true;
            }
        }
        if (object.prev != 0) {
            Object memory prev = self.objects[object.prev];
            if (prev.rank < _rank) {
                needMove = true;
            }
        }
        if (needMove) {
            removeByAddress(self, _data);
            insert(self, _rank, _data);
        } else {
            self.objects[id].rank = _rank;
        }
    }

    /**
     * @dev Insert the object immediately before the one with the closest lower rank.
     * WARNING: This method loops through the whole list before inserting, and therefore limits the
     * size of the list to a few tens of thousands of objects before becoming unusable. For a scalable
     * contract make _insertBefore public but check prev and next on insertion.
     */
    function insert(RankedList storage self, int256 _rank, address _data)
    internal
    {
        uint256 nextId = findRank(self, _rank);
        if (nextId == 0) {
            _addTail(self, _rank, _data);
        }
        else {
            _insertBefore(self, nextId, _rank, _data);
        }
    }

    function replace(RankedList storage self, address oldData, address newData)
    internal
    {
        Object memory oldObject = self.objects[uint256(uint160(oldData))];
        remove(self, oldObject.id);
        uint256 newObjectId = _createObject(self, oldObject.rank, newData);
        _link(self, oldObject.prev, newObjectId);
        _link(self, newObjectId, oldObject.next);
        if (self.head == oldObject.id) {
            _setHead(self, newObjectId);
        }
        if (self.tail == oldObject.id) {
            _setTail(self, newObjectId);
        }
    }

    function removeByAddress(RankedList storage self, address _data)
    internal
    {
        remove(self, uint256(uint160(_data)));
    }

    /**
     * @dev Remove the Object denoted by `_id` from the List.
     */
    function remove(RankedList storage self, uint256 _id)
    internal
    {
        Object memory removeObject = self.objects[_id];
        if (removeObject.id != 0) {
            if (self.head == _id && self.tail == _id) {
                _setHead(self, 0);
                _setTail(self, 0);
            }
            else if (self.head == _id) {
                _setHead(self, removeObject.next);
                self.objects[removeObject.next].prev = 0;
            }
            else if (self.tail == _id) {
                _setTail(self, removeObject.prev);
                self.objects[removeObject.prev].next = 0;
            }
            else {
                _link(self, removeObject.prev, removeObject.next);
            }
            delete self.objects[removeObject.id];
            self.size--;
        }
        //        emit ObjectRemoved(_id);
    }

    /**
     * @dev Insert a new Object as the new Head with `_data` in the data field.
     */
    function _addHead(RankedList storage self, int256 _rank, address _data)
    internal
    {
        uint256 objectId = _createObject(self, _rank, _data);
        _link(self, objectId, self.head);
        _setHead(self, objectId);
        if (self.tail == 0) _setTail(self, objectId);
    }

    /**
     * @dev Insert a new Object as the new Tail with `_data` in the data field.
     */
    function _addTail(RankedList storage self, int256 _rank, address _data)
    internal
    {
        if (self.head == 0) {
            _addHead(self, _rank, _data);
        }
        else {
            uint256 objectId = _createObject(self, _rank, _data);
            _link(self, self.tail, objectId);
            _setTail(self, objectId);
        }
    }

    /**
     * @dev Insert a new Object after the Object denoted by `_id` with `_data` in the data field.
     */
    function _insertAfter(RankedList storage self, uint256 _prevId, int256 _rank, address _data)
    internal
    {
        if (_prevId == self.tail) {
            _addTail(self, _rank, _data);
        }
        else {
            Object memory prevObject = self.objects[_prevId];
            Object memory nextObject = self.objects[prevObject.next];
            uint256 newObjectId = _createObject(self, _rank, _data);
            _link(self, newObjectId, nextObject.id);
            _link(self, prevObject.id, newObjectId);
        }
    }

    /**
     * @dev Insert a new Object before the Object denoted by `_id` with `_data` in the data field.
     */
    function _insertBefore(RankedList storage self, uint256 _nextId, int256 _rank, address _data)
    internal
    {
        if (_nextId == self.head) {
            _addHead(self, _rank, _data);
        }
        else {
            _insertAfter(self, self.objects[_nextId].prev, _rank, _data);
        }
    }

    /**
     * @dev Internal function to update the Head pointer.
     */
    function _setHead(RankedList storage self, uint256 _id)
    internal
    {
        self.head = _id;
        //        emit NewHead(_id);
    }

    /**
     * @dev Internal function to update the Tail pointer.
     */
    function _setTail(RankedList storage self, uint256 _id)
    internal
    {
        self.tail = _id;
        //        emit NewTail(_id);
    }

    /**
     * @dev Internal function to create an unlinked Object.
     */
    function _createObject(RankedList storage self, int256 _rank, address _data)
    internal
    returns (uint256)
    {
        uint256 newId = uint256(uint160(_data));
        require(self.objects[newId].id == 0);

        self.size++;

        Object memory object = Object(
            newId,
            0,
            0,
            _rank,
            _data
        );
        self.objects[object.id] = object;
        //        emit ObjectCreated(
        //            object.id,
        //            object.rank,
        //            object.data
        //        );
        return object.id;
    }

    /**
     * @dev Internal function to link an Object to another.
     */
    function _link(RankedList storage self, uint256 _prevId, uint256 _nextId)
    internal
    {
        if (_prevId != 0 && _nextId != 0) {
            self.objects[_prevId].next = _nextId;
            self.objects[_nextId].prev = _prevId;
            //            emit ObjectsLinked(_prevId, _nextId);
        }
    }
}
