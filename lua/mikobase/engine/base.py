class BaseEngine:

    def q0(self, query):
        raise NotImplementedError

    def record_by_pk(self, pk):
        return self.q0({'action': 'select', 'pk': pk})

    def by_class(self, class_name):
        return self.q0({'action': 'select', 'class': class_name})

    def validate(self, query):
        return self.validator.run_all(query)

    @property
    def validator(self):
        raise NotImplementedError
