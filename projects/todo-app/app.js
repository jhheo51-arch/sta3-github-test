const STORAGE_KEY = "class-todo-items";

const form = document.querySelector("#todo-form");
const input = document.querySelector("#todo-input");
const priorityInput = document.querySelector("#todo-priority");
const dateInput = document.querySelector("#todo-date");
const searchInput = document.querySelector("#todo-search");
const list = document.querySelector("#todo-list");
const remainingCount = document.querySelector("#remaining-count");
const emptyState = document.querySelector("#empty-state");
const completionCelebration = document.querySelector("#completion-celebration");
const calendarTitle = document.querySelector("#calendar-title");
const calendarGrid = document.querySelector("#calendar-grid");
const selectedDateTitle = document.querySelector("#selected-date-title");
const previousMonthButton = document.querySelector("#previous-month");
const nextMonthButton = document.querySelector("#next-month");
const statusFilterButtons = document.querySelectorAll(".status-filter-button");

function toDateKey(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function fromDateKey(dateKey) {
  const [year, month, day] = dateKey.split("-").map(Number);
  return new Date(year, month - 1, day);
}

function isDateKey(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value || "");
}

const todayKey = toDateKey(new Date());
let selectedDate = todayKey;
let calendarMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1);
let selectedStatusFilter = "all";

const PRIORITIES = {
  high: "높음",
  medium: "보통",
  low: "낮음",
};

let todos = loadTodos();

function loadTodos() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (Array.isArray(saved)) {
      return saved.map((todo) => ({
        ...todo,
        priority: PRIORITIES[todo.priority] ? todo.priority : "medium",
        date: isDateKey(todo.date) ? todo.date : todayKey,
      }));
    }
  } catch (_) {}

  return [
    { id: crypto.randomUUID(), title: "강의 자료 만들기", completed: false, priority: "medium", date: todayKey },
    { id: crypto.randomUUID(), title: "이메일 답장하기", completed: true, priority: "medium", date: todayKey },
    { id: crypto.randomUUID(), title: "운동하기", completed: false, priority: "medium", date: todayKey },
  ];
}

function saveTodos() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(todos));
}

function renderCalendar() {
  const year = calendarMonth.getFullYear();
  const month = calendarMonth.getMonth();
  const firstWeekday = new Date(year, month, 1).getDay();
  const lastDay = new Date(year, month + 1, 0).getDate();
  const todoCounts = todos.reduce((counts, todo) => {
    counts[todo.date] = (counts[todo.date] || 0) + 1;
    return counts;
  }, {});

  calendarTitle.textContent = `${year}년 ${month + 1}월`;
  calendarGrid.innerHTML = "";

  for (let index = 0; index < firstWeekday; index += 1) {
    const spacer = document.createElement("span");
    spacer.className = "calendar-spacer";
    spacer.setAttribute("aria-hidden", "true");
    calendarGrid.appendChild(spacer);
  }

  for (let day = 1; day <= lastDay; day += 1) {
    const dateKey = toDateKey(new Date(year, month, day));
    const count = todoCounts[dateKey] || 0;
    const isToday = dateKey === todayKey;
    const isSelected = dateKey === selectedDate;
    const dayButton = document.createElement("button");

    dayButton.type = "button";
    dayButton.className = `calendar-day${isToday ? " today" : ""}${isSelected ? " selected" : ""}`;
    dayButton.dataset.date = dateKey;
    dayButton.setAttribute("aria-pressed", String(isSelected));
    dayButton.setAttribute(
      "aria-label",
      `${month + 1}월 ${day}일${isToday ? ", 오늘" : ""}, 할 일 ${count}개`
    );

    const number = document.createElement("span");
    number.className = "day-number";
    number.textContent = String(day);
    dayButton.appendChild(number);

    if (isToday || count > 0) {
      const detailLabel = document.createElement("span");
      detailLabel.className = "day-details";

      if (isToday) {
        const todayLabel = document.createElement("span");
        todayLabel.className = "today-label";
        todayLabel.textContent = "오늘";
        detailLabel.appendChild(todayLabel);
      }

      if (count > 0) {
        const countLabel = document.createElement("span");
        countLabel.className = "day-count";
        countLabel.textContent = `${count}개`;
        detailLabel.appendChild(countLabel);
      }

      dayButton.appendChild(detailLabel);
    }

    dayButton.addEventListener("click", () => selectDate(dateKey));
    dayButton.addEventListener("keydown", (event) => handleCalendarKey(event, dateKey));
    calendarGrid.appendChild(dayButton);
  }
}

function renderTodos() {
  list.innerHTML = "";
  const selectedTodos = todos.filter((todo) => todo.date === selectedDate);
  const statusFilteredTodos = selectedTodos.filter((todo) => {
    if (selectedStatusFilter === "active") return !todo.completed;
    if (selectedStatusFilter === "completed") return todo.completed;
    return true;
  });
  const searchQuery = searchInput.value.trim().toLocaleLowerCase("ko-KR");
  const visibleTodos = statusFilteredTodos.filter((todo) =>
    todo.title.toLocaleLowerCase("ko-KR").includes(searchQuery)
  );

  visibleTodos.forEach((todo) => {
    const item = document.createElement("li");
    item.className = `todo-item${todo.completed ? " completed" : ""}`;

    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = todo.completed;
    checkbox.setAttribute("aria-label", `${todo.title} 완료 여부`);
    checkbox.addEventListener("change", () => toggleTodo(todo.id));

    const title = document.createElement("span");
    title.className = "title";
    title.textContent = todo.title;

    const priority = document.createElement("select");
    priority.className = `priority-select priority-${todo.priority}`;
    priority.setAttribute("aria-label", `${todo.title} 우선순위`);

    Object.entries(PRIORITIES).forEach(([value, label]) => {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = label;
      option.selected = todo.priority === value;
      priority.appendChild(option);
    });

    priority.addEventListener("change", (event) =>
      changePriority(todo.id, event.target.value)
    );

    const deleteButton = document.createElement("button");
    deleteButton.type = "button";
    deleteButton.className = "delete-button";
    deleteButton.textContent = "삭제";
    deleteButton.addEventListener("click", () => deleteTodo(todo.id));

    item.append(checkbox, title, priority, deleteButton);
    list.appendChild(item);
  });

  const remaining = selectedTodos.filter((todo) => !todo.completed).length;
  remainingCount.textContent = `${remaining}개의 할 일 남음`;
  emptyState.textContent = searchQuery
    ? "검색 결과가 없어요."
    : {
        all: "아직 할 일이 없어요.",
        active: "진행 중인 할 일이 없어요.",
        completed: "완료한 할 일이 없어요.",
      }[selectedStatusFilter];
  emptyState.hidden = visibleTodos.length > 0;
  completionCelebration.hidden = selectedTodos.length === 0 || remaining > 0;
  statusFilterButtons.forEach((button) => {
    button.setAttribute(
      "aria-pressed",
      String(button.dataset.filter === selectedStatusFilter)
    );
  });
  selectedDateTitle.textContent = new Intl.DateTimeFormat("ko-KR", {
    year: "numeric",
    month: "long",
    day: "numeric",
    weekday: "long",
  }).format(fromDateKey(selectedDate));
}

function render() {
  renderCalendar();
  renderTodos();
  dateInput.value = selectedDate;
}

function addTodo(title, date, priority = "medium") {
  todos.unshift({ id: crypto.randomUUID(), title, completed: false, date, priority });
  saveTodos();
  render();
}

function toggleTodo(id) {
  todos = todos.map((todo) =>
    todo.id === id ? { ...todo, completed: !todo.completed } : todo
  );
  saveTodos();
  render();
}

function deleteTodo(id) {
  todos = todos.filter((todo) => todo.id !== id);
  saveTodos();
  render();
}

function changePriority(id, priority) {
  if (!PRIORITIES[priority]) return;

  todos = todos.map((todo) =>
    todo.id === id ? { ...todo, priority } : todo
  );
  saveTodos();
  render();
}

function selectDate(dateKey, focusSelected = false) {
  if (!isDateKey(dateKey)) return;

  selectedDate = dateKey;
  const date = fromDateKey(dateKey);
  calendarMonth = new Date(date.getFullYear(), date.getMonth(), 1);
  render();

  if (focusSelected) {
    calendarGrid.querySelector(`[data-date="${selectedDate}"]`)?.focus();
  }
}

function shiftMonth(offset) {
  const selected = fromDateKey(selectedDate);
  const targetYear = calendarMonth.getFullYear();
  const targetMonth = calendarMonth.getMonth() + offset;
  const lastDay = new Date(targetYear, targetMonth + 1, 0).getDate();
  const targetDate = new Date(targetYear, targetMonth, Math.min(selected.getDate(), lastDay));
  selectDate(toDateKey(targetDate), true);
}

function handleCalendarKey(event, dateKey) {
  const offsets = {
    ArrowLeft: -1,
    ArrowRight: 1,
    ArrowUp: -7,
    ArrowDown: 7,
  };
  const offset = offsets[event.key];
  if (!offset) return;

  event.preventDefault();
  const nextDate = fromDateKey(dateKey);
  nextDate.setDate(nextDate.getDate() + offset);
  selectDate(toDateKey(nextDate), true);
}

previousMonthButton.addEventListener("click", () => shiftMonth(-1));
nextMonthButton.addEventListener("click", () => shiftMonth(1));
dateInput.addEventListener("change", () => selectDate(dateInput.value));
statusFilterButtons.forEach((button) => {
  button.addEventListener("click", () => {
    selectedStatusFilter = button.dataset.filter;
    renderTodos();
  });
});
searchInput.addEventListener("input", renderTodos);

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const title = input.value.trim();
  if (!title) return;

  addTodo(title, dateInput.value || selectedDate, priorityInput.value);
  input.value = "";
  priorityInput.value = "medium";
  input.focus();
});

render();
