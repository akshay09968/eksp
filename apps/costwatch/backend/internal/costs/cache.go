package costs

import (
	"sync"
	"sync/atomic"
	"time"
)

// cache is a TTL cache with request coalescing (singleflight). Caching here is
// a correctness feature, not an optimization: Cost Explorer bills ~$0.01 per
// request and refreshes data ~3x/day — an uncached dashboard tab left open
// would quietly buy a lot of nothing.
type cache struct {
	mu       sync.Mutex
	ttl      time.Duration
	entries  map[string]cacheEntry
	inflight map[string]*inflightCall

	hits   atomic.Int64
	misses atomic.Int64
}

type cacheEntry struct {
	val any
	exp time.Time
}

type inflightCall struct {
	done chan struct{}
	val  any
	err  error
}

func newCache(ttl time.Duration) *cache {
	return &cache{
		ttl:      ttl,
		entries:  make(map[string]cacheEntry),
		inflight: make(map[string]*inflightCall),
	}
}

// do returns the cached value for key, or runs fn exactly once even under
// concurrency. The bool reports whether the value came from cache.
func (c *cache) do(key string, fn func() (any, error)) (any, bool, error) {
	if c.ttl <= 0 {
		val, err := fn()
		return val, false, err
	}

	c.mu.Lock()
	if e, ok := c.entries[key]; ok && time.Now().Before(e.exp) {
		c.mu.Unlock()
		c.hits.Add(1)
		return e.val, true, nil
	}
	if call, ok := c.inflight[key]; ok {
		c.mu.Unlock()
		<-call.done
		return call.val, false, call.err
	}

	call := &inflightCall{done: make(chan struct{})}
	c.inflight[key] = call
	c.mu.Unlock()
	c.misses.Add(1)

	call.val, call.err = fn()
	close(call.done)

	c.mu.Lock()
	delete(c.inflight, key)
	if call.err == nil {
		c.entries[key] = cacheEntry{val: call.val, exp: time.Now().Add(c.ttl)}
	}
	c.mu.Unlock()

	return call.val, false, call.err
}

type CacheStats struct {
	Entries int   `json:"entries"`
	Hits    int64 `json:"hits"`
	Misses  int64 `json:"misses"`
}

func (c *cache) stats() CacheStats {
	c.mu.Lock()
	defer c.mu.Unlock()
	return CacheStats{
		Entries: len(c.entries),
		Hits:    c.hits.Load(),
		Misses:  c.misses.Load(),
	}
}
