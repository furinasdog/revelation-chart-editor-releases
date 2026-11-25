using System.Collections.Generic;

namespace RevelationHub;

// Workers only split unclaimed bytes. A short read or a retry keeps the in-flight
// reservation on its original worker until it has written those bytes to disk.
internal sealed class DownloadRanges(long start, long end)
{
    internal sealed class Piece(long next, long limit)
    {
        internal long Next = next;
        internal long End = limit;
        internal long Reserved = next;
    }

    internal const int MinimumPiece = 1024 * 1024;
    private readonly List<Piece> active = new();
    private bool started;

    internal Piece Take()
    {
        lock (active)
        {
            if (!started)
            {
                started = true;
                if (start == end) return null;
                var first = new Piece(start, end);
                active.Add(first);
                return first;
            }

            Piece largest = null;
            long available = 0;
            foreach (var piece in active)
            {
                long remaining = piece.End - piece.Reserved;
                if (remaining > available) { largest = piece; available = remaining; }
            }
            if (available < 2L * MinimumPiece) return null;
            long split = largest.End - available / 2;
            var tail = new Piece(split, largest.End);
            largest.End = split;
            active.Add(tail);
            return tail;
        }
    }

    internal long EndOf(Piece piece) { lock (active) return piece.End; }

    internal int Reserve(Piece piece, int capacity)
    {
        lock (active)
        {
            int count = (int)System.Math.Min(capacity, piece.End - piece.Next);
            piece.Reserved = piece.Next + count;
            return count;
        }
    }

    internal void Advance(Piece piece, int count)
    {
        lock (active) { piece.Next += count; piece.Reserved = piece.Next; }
    }

    internal void Finish(Piece piece) { lock (active) active.Remove(piece); }
}
