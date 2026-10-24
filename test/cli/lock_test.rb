class LockClock
  def initialize(now)
    @now = now
  end

  def now_ms
    @now
  end
end

class LockSleeper
  attr_reader :slept

  def initialize
    @slept = []
  end

  def sleep_ms(ms)
    @slept << ms
  end
end

class LockTest < Picotest::Test
  def tmp_path(name)
    @paths = [] unless @paths
    path = "/tmp/phomemo-cli-locktest-#{name}-#{Machine.board_millis}.lock"
    @paths << path
    path
  end

  def teardown
    return unless @paths
    i = 0
    while i < @paths.size
      File.delete(@paths[i]) if File.exist?(@paths[i])
      i += 1
    end
    @paths = []
  end

  def test_the_production_lock_path_is_fixed
    assert_equal "/tmp/phomemo-print.lock", PhomemoCLI::Lock::DEFAULT_PATH
    assert_equal 1500, PhomemoCLI::Lock::GAP_MS
  end

  def test_a_second_holder_is_refused_without_waiting
    path = tmp_path("second")
    a = PhomemoCLI::Lock.acquire(path)
    assert_not_nil a
    assert_nil PhomemoCLI::Lock.acquire(path)
    a.release(now_ms: 1000)
    b = PhomemoCLI::Lock.acquire(path)
    assert_not_nil b
    b.release(now_ms: 2000)
  end

  def test_the_release_time_is_handed_to_the_next_holder
    path = tmp_path("handover")
    a = PhomemoCLI::Lock.acquire(path)
    assert_nil a.last_finished_ms
    a.release(now_ms: 123_456)
    b = PhomemoCLI::Lock.acquire(path)
    assert_equal 123_456, b.last_finished_ms
    b.release(now_ms: 200_000)
    c = PhomemoCLI::Lock.acquire(path)
    assert_equal 200_000, c.last_finished_ms
    c.release(now_ms: 300_000)
  end

  def test_the_gap_since_the_last_job_is_padded_to_1500ms
    clock = LockClock.new(10_000)
    sleeper = LockSleeper.new
    lock = PhomemoCLI::Lock.acquire(tmp_path("gap"), last_finished_ms: 9_000)
    lock.wait_for_gap(clock, sleeper)
    assert_equal [500], sleeper.slept
    lock.release(now_ms: 10_500)
  end

  def test_the_gap_uses_the_time_stored_in_the_file
    path = tmp_path("stored")
    PhomemoCLI::Lock.acquire(path).release(now_ms: 7_000)
    sleeper = LockSleeper.new
    lock = PhomemoCLI::Lock.acquire(path)
    lock.wait_for_gap(LockClock.new(7_400), sleeper)
    assert_equal [1100], sleeper.slept
    lock.release(now_ms: 8_500)
  end

  def test_no_wait_when_1500ms_have_already_passed
    sleeper = LockSleeper.new
    lock = PhomemoCLI::Lock.acquire(tmp_path("passed"), last_finished_ms: 9_000)
    lock.wait_for_gap(LockClock.new(10_500), sleeper)
    lock.wait_for_gap(LockClock.new(20_000), sleeper)
    assert_equal [], sleeper.slept
    lock.release(now_ms: 20_000)
  end

  def test_no_wait_for_the_first_job_or_after_the_clock_restarted
    sleeper = LockSleeper.new
    first = PhomemoCLI::Lock.acquire(tmp_path("first"))
    first.wait_for_gap(LockClock.new(100), sleeper)
    first.release(now_ms: 100)
    after_reboot = PhomemoCLI::Lock.acquire(tmp_path("reboot"), last_finished_ms: 900_000)
    after_reboot.wait_for_gap(LockClock.new(100), sleeper)
    assert_equal [], sleeper.slept
    after_reboot.release(now_ms: 100)
  end
end
